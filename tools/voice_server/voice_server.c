/*
 * Procedural World voice server: the game's built-in natural voices.
 *
 * A tiny local HTTP server that speaks lines with the Kokoro neural voice model through
 * sherpa-onnx (both Apache-2.0). It answers the same request as an OpenAI-compatible
 * voice server, so the game talks to it like any other:
 *
 *   POST /v1/audio/speech  {"input": "...", "voice": "42@en-GB-scotland", "speed": 1.0}
 *        -> raw 16-bit mono PCM at 24 kHz (or a WAV with "response_format": "wav")
 *   POST /v1/audio/transcriptions  a 16-bit PCM WAV (multipart "file", or the raw body)
 *        -> {"text": "..."}: speech to text with NVIDIA's Parakeet TDT 0.6B v2 (CC-BY-4.0),
 *        when the voice pack has it in stt/ (loaded in the background at start)
 *   GET  /health           -> {"ok": true, "token": "<--token>", "voices": N, "stt": "ready"}
 *
 * "voice" is a speaker number in the voice table, optionally followed by "@" and the
 * eSpeak NG accent its words are sounded out in (en, en-GB-x-rp, en-GB-scotland,
 * en-GB-x-gbclan, en-GB-x-gbcwmd, en-US, en-US-nyc, en-029). The game starts it with a
 * random port and token and it only listens on 127.0.0.1. It quits when the game that
 * started it (--parent-pid) is gone.
 *
 * Build: tools/voice_server/build.sh (Linux and, with MinGW, Windows).
 */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>
typedef SOCKET sock_t;
#define CLOSESOCK closesocket
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int sock_t;
#define INVALID_SOCKET (-1)
#define CLOSESOCK close
#endif

#include "sherpa-onnx/c-api/c-api.h"

#define MAX_BODY (64 * 1024)
#define MAX_UPLOAD (4 * 1024 * 1024) /* a recording: 30 s at 48 kHz stereo is under 6 MB, 16 kHz mono 1 MB */
#define MAX_TEXT 2000

static const SherpaOnnxOfflineTts *tts;
static char token[128] = "";
static int num_voices = 0;
static const SherpaOnnxOfflineRecognizer *stt;
/* Speech to text: "none" (no model in the pack), "loading", "ready" or "failed". */
static volatile const char *stt_state = "none";
static char stt_dir[1024];
static int stt_threads = 4;

/* ---- the game that started us ------------------------------------------------------ */

#ifdef _WIN32
static DWORD WINAPI watch_parent(LPVOID arg) {
  HANDLE h = OpenProcess(SYNCHRONIZE, FALSE, (DWORD)(uintptr_t)arg);
  if (h == NULL) exit(0);
  WaitForSingleObject(h, INFINITE);
  exit(0);
  return 0;
}
static void start_watch(long pid) { CreateThread(NULL, 0, watch_parent, (LPVOID)(uintptr_t)pid, 0, NULL); }
#else
static void *watch_parent(void *arg) {
  long pid = (long)(intptr_t)arg;
  for (;;) {
    if (kill((pid_t)pid, 0) != 0 && errno == ESRCH) exit(0);
    sleep(1);
  }
  return NULL;
}
static void start_watch(long pid) {
  pthread_t t;
  pthread_create(&t, NULL, watch_parent, (void *)(intptr_t)pid);
  pthread_detach(t);
}
#endif

/* ---- a very small JSON reader (flat objects only) ---------------------------------- */

static void put_utf8(char **o, char *end, unsigned cp) {
  char *p = *o;
  if (cp < 0x80) { if (p < end) *p++ = (char)cp; }
  else if (cp < 0x800) { if (p + 1 < end) { *p++ = (char)(0xC0 | cp >> 6); *p++ = (char)(0x80 | (cp & 0x3F)); } }
  else if (cp < 0x10000) { if (p + 2 < end) { *p++ = (char)(0xE0 | cp >> 12); *p++ = (char)(0x80 | ((cp >> 6) & 0x3F)); *p++ = (char)(0x80 | (cp & 0x3F)); } }
  else if (p + 3 < end) { *p++ = (char)(0xF0 | cp >> 18); *p++ = (char)(0x80 | ((cp >> 12) & 0x3F)); *p++ = (char)(0x80 | ((cp >> 6) & 0x3F)); *p++ = (char)(0x80 | (cp & 0x3F)); }
  *o = p;
}

static unsigned hex4(const char *s) {
  unsigned v = 0;
  for (int i = 0; i < 4; i++) {
    char c = s[i];
    v <<= 4;
    if (c >= '0' && c <= '9') v |= (unsigned)(c - '0');
    else if (c >= 'a' && c <= 'f') v |= (unsigned)(c - 'a' + 10);
    else if (c >= 'A' && c <= 'F') v |= (unsigned)(c - 'A' + 10);
    else return 0xFFFFFFFF;
  }
  return v;
}

/* Finds "key": in a flat JSON object; returns a pointer to its value or NULL. */
static const char *json_find(const char *js, const char *key) {
  size_t kl = strlen(key);
  for (const char *p = js; (p = strchr(p, '"')) != NULL; p++) {
    if (strncmp(p + 1, key, kl) == 0 && p[kl + 1] == '"') {
      const char *q = p + kl + 2;
      while (*q == ' ' || *q == '\t' || *q == '\r' || *q == '\n') q++;
      if (*q != ':') continue;
      q++;
      while (*q == ' ' || *q == '\t' || *q == '\r' || *q == '\n') q++;
      return q;
    }
    /* skip over this string so keys inside values are never matched */
    for (p++; *p && *p != '"'; p++)
      if (*p == '\\' && p[1]) p++;
    if (!*p) break;
  }
  return NULL;
}

static int json_string(const char *js, const char *key, char *out, size_t cap) {
  const char *p = json_find(js, key);
  if (p == NULL || *p != '"') return 0;
  char *o = out, *end = out + cap - 1;
  for (p++; *p && *p != '"'; p++) {
    if (*p != '\\') { if (o < end) *o++ = *p; continue; }
    p++;
    switch (*p) {
      case 'n': case 'r': case 't': if (o < end) *o++ = ' '; break;
      case 'b': case 'f': break;
      case 'u': {
        unsigned cp = hex4(p + 1);
        if (cp == 0xFFFFFFFF) return 0;
        p += 4;
        if (cp >= 0xD800 && cp < 0xDC00 && p[1] == '\\' && p[2] == 'u') {
          unsigned lo = hex4(p + 3);
          if (lo >= 0xDC00 && lo < 0xE000) { cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00); p += 6; }
        }
        put_utf8(&o, end, cp);
        break;
      }
      case 0: *o = 0; return 0;
      default: if (o < end) *o++ = *p;
    }
  }
  *o = 0;
  return 1;
}

static double json_number(const char *js, const char *key, double def) {
  const char *p = json_find(js, key);
  if (p == NULL) return def;
  if (*p == '"') p++; /* some clients send numbers as strings */
  char *e;
  double v = strtod(p, &e);
  return e == p ? def : v;
}

/* ---- HTTP ---------------------------------------------------------------------------- */

static int send_all(sock_t s, const char *b, size_t n) {
  while (n > 0) {
    int k = send(s, b, (int)(n > 1 << 20 ? 1 << 20 : n), 0);
    if (k <= 0) return -1;
    b += k;
    n -= (size_t)k;
  }
  return 0;
}

static void reply(sock_t s, int code, const char *type, const char *body, size_t n) {
  char head[256];
  int hl = snprintf(head, sizeof head, "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %zu\r\nConnection: close\r\n\r\n",
                    code, code == 200 ? "OK" : (code == 404 ? "Not Found" : (code == 401 ? "Unauthorized" : "Bad Request")), type, n);
  send_all(s, head, (size_t)hl);
  send_all(s, body, n);
}

static void reply_error(sock_t s, int code, const char *msg) {
  char b[512];
  int n = snprintf(b, sizeof b, "{\"error\": {\"message\": \"%s\"}}", msg);
  reply(s, code, "application/json", b, (size_t)n);
}

static void put_le(char *p, uint32_t v, int bytes) {
  for (int i = 0; i < bytes; i++) p[i] = (char)((v >> (8 * i)) & 0xFF);
}

static void speak(sock_t s, const char *body) {
  static char text[MAX_TEXT * 4 + 1];
  char voice[96] = "0", fmt[16] = "pcm", lang[64] = "";
  if (tts == NULL) { reply_error(s, 404, "this voice pack has no voices"); return; }
  if (!json_string(body, "input", text, sizeof text) || text[0] == 0) { reply_error(s, 400, "no input"); return; }
  json_string(body, "voice", voice, sizeof voice);
  json_string(body, "response_format", fmt, sizeof fmt);
  char *at = strchr(voice, '@');
  if (at) {
    *at = 0;
    snprintf(lang, sizeof lang, "%s", at + 1);
    for (char *c = lang; *c; c++) /* accent names are plain words: never pass on anything else */
      if (!((*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') || (*c >= '0' && *c <= '9') || *c == '-')) { lang[0] = 0; break; }
  }
  int sid = atoi(voice);
  if (sid < 0 || sid >= num_voices) sid = 0;
  float speed = (float)json_number(body, "speed", 1.0);
  if (speed < 0.5f) speed = 0.5f;
  if (speed > 2.0f) speed = 2.0f;

  char extra[128] = "";
  if (lang[0]) snprintf(extra, sizeof extra, "{\"lang\": \"%s\"}", lang);
  SherpaOnnxGenerationConfig cfg;
  memset(&cfg, 0, sizeof cfg);
  cfg.sid = sid;
  cfg.speed = speed;
  cfg.silence_scale = 0.2f;
  cfg.extra = lang[0] ? extra : NULL;
  const SherpaOnnxGeneratedAudio *a = SherpaOnnxOfflineTtsGenerateWithConfig(tts, text, &cfg, NULL, NULL);
  if (a == NULL || a->n <= 0) {
    if (a) SherpaOnnxDestroyOfflineTtsGeneratedAudio(a);
    reply_error(s, 400, "could not speak that");
    return;
  }
  int wav = strcmp(fmt, "wav") == 0;
  size_t hdr = wav ? 44 : 0, n = (size_t)a->n * 2;
  char *out = malloc(hdr + n);
  if (out == NULL) { SherpaOnnxDestroyOfflineTtsGeneratedAudio(a); reply_error(s, 400, "out of memory"); return; }
  if (wav) {
    memcpy(out, "RIFF", 4); put_le(out + 4, (uint32_t)(36 + n), 4); memcpy(out + 8, "WAVEfmt ", 8);
    put_le(out + 16, 16, 4); put_le(out + 20, 1, 2); put_le(out + 22, 1, 2); put_le(out + 24, (uint32_t)a->sample_rate, 4);
    put_le(out + 28, (uint32_t)a->sample_rate * 2, 4); put_le(out + 32, 2, 2); put_le(out + 34, 16, 2);
    memcpy(out + 36, "data", 4); put_le(out + 40, (uint32_t)n, 4);
  }
  for (int i = 0; i < a->n; i++) {
    float v = a->samples[i] * 32767.0f;
    int16_t q = (int16_t)(v > 32767.0f ? 32767 : (v < -32768.0f ? -32768 : v));
    put_le(out + hdr + 2 * (size_t)i, (uint16_t)q, 2);
  }
  reply(s, 200, wav ? "audio/wav" : "audio/pcm", out, hdr + n);
  free(out);
  SherpaOnnxDestroyOfflineTtsGeneratedAudio(a);
}

/* ---- speech to text ------------------------------------------------------------------ */

static void sleep_ms(int ms) {
#ifdef _WIN32
  Sleep((DWORD)ms);
#else
  usleep((useconds_t)ms * 1000);
#endif
}

static void load_stt(void) {
  char enc[1100], dec[1100], join[1100], toks[1100];
  snprintf(enc, sizeof enc, "%s/encoder.int8.onnx", stt_dir);
  snprintf(dec, sizeof dec, "%s/decoder.int8.onnx", stt_dir);
  snprintf(join, sizeof join, "%s/joiner.int8.onnx", stt_dir);
  snprintf(toks, sizeof toks, "%s/tokens.txt", stt_dir);
  SherpaOnnxOfflineRecognizerConfig c;
  memset(&c, 0, sizeof c);
  c.feat_config.sample_rate = 16000;
  c.feat_config.feature_dim = 80;
  c.model_config.transducer.encoder = enc;
  c.model_config.transducer.decoder = dec;
  c.model_config.transducer.joiner = join;
  c.model_config.tokens = toks;
  c.model_config.num_threads = stt_threads;
  c.model_config.provider = "cpu";
  c.model_config.model_type = "nemo_transducer";
  c.decoding_method = "greedy_search";
  stt = SherpaOnnxCreateOfflineRecognizer(&c);
  stt_state = stt ? "ready" : "failed";
  fprintf(stderr, "voice_server: speech to text %s\n", stt ? "ready" : "could not load");
}

#ifdef _WIN32
static DWORD WINAPI stt_thread(LPVOID arg) { (void)arg; load_stt(); return 0; }
static void start_stt(void) { CreateThread(NULL, 0, stt_thread, NULL, 0, NULL); }
#else
static void *stt_thread(void *arg) { (void)arg; load_stt(); return NULL; }
static void start_stt(void) {
  pthread_t t;
  pthread_create(&t, NULL, stt_thread, NULL);
  pthread_detach(t);
}
#endif

static uint32_t get_le(const unsigned char *p, int bytes) {
  uint32_t v = 0;
  for (int i = bytes - 1; i >= 0; i--) v = (v << 8) | p[i];
  return v;
}

/* Finds the WAV in a request body (a multipart upload or the bare file) and reads its
   16-bit PCM as mono floats. Returns the sample count (0 if there is no usable WAV). */
static long read_wav(const unsigned char *b, size_t n, float **out, int *rate) {
  const unsigned char *w = NULL;
  for (size_t i = 0; i + 12 <= n; i++)
    if (memcmp(b + i, "RIFF", 4) == 0 && memcmp(b + i + 8, "WAVE", 4) == 0) { w = b + i; break; }
  if (w == NULL) return 0;
  const unsigned char *end = b + n, *p = w + 12;
  int ch = 0, bits = 0, fmt = 0;
  *rate = 0;
  while (p + 8 <= end) {
    uint32_t len = get_le(p + 4, 4);
    const unsigned char *d = p + 8;
    if (memcmp(p, "fmt ", 4) == 0 && d + 16 <= end) {
      fmt = (int)get_le(d, 2); ch = (int)get_le(d + 2, 2); *rate = (int)get_le(d + 4, 4); bits = (int)get_le(d + 14, 2);
    } else if (memcmp(p, "data", 4) == 0) {
      if ((fmt != 1 && fmt != 0xFFFE) || bits != 16 || ch < 1 || *rate < 8000) return 0;
      size_t avail = (size_t)(end - d);
      if (len > avail) len = (uint32_t)avail; /* a writer that never filled in the size */
      long frames = (long)(len / (2u * (unsigned)ch));
      float *f = malloc(sizeof(float) * (size_t)(frames > 0 ? frames : 1));
      if (f == NULL) return 0;
      for (long i = 0; i < frames; i++) {
        long sum = 0;
        for (int k = 0; k < ch; k++) sum += (int16_t)get_le(d + 2 * ((size_t)i * ch + k), 2);
        f[i] = (float)sum / (32768.0f * ch);
      }
      *out = f;
      return frames;
    }
    p = d + len + (len & 1);
  }
  return 0;
}

static void transcribe(sock_t s, const char *body, size_t n) {
  if (strcmp((const char *)stt_state, "none") == 0) { reply_error(s, 404, "this voice pack has no speech recognition"); return; }
  for (int i = 0; i < 1200 && strcmp((const char *)stt_state, "loading") == 0; i++) sleep_ms(50); /* still loading: up to a minute */
  if (stt == NULL) { reply_error(s, 400, "speech recognition did not load"); return; }
  float *pcm = NULL;
  int rate = 0;
  long frames = read_wav((const unsigned char *)body, n, &pcm, &rate);
  if (frames <= 0) { free(pcm); reply_error(s, 400, "send a 16-bit PCM WAV"); return; }
  const SherpaOnnxOfflineStream *st = SherpaOnnxCreateOfflineStream(stt);
  SherpaOnnxAcceptWaveformOffline(st, rate, pcm, (int32_t)frames);
  SherpaOnnxDecodeOfflineStream(stt, st);
  const SherpaOnnxOfflineRecognizerResult *r = SherpaOnnxGetOfflineStreamResult(st);
  const char *t = (r && r->text) ? r->text : "";
  size_t tl = strlen(t);
  char *o = malloc(tl * 6 + 32), *q = o;
  if (o == NULL) { reply_error(s, 400, "out of memory"); }
  else {
    q += sprintf(q, "{\"text\": \"");
    for (const char *c = t; *c; c++) {
      unsigned char u = (unsigned char)*c;
      if (u == '"' || u == '\\') { *q++ = '\\'; *q++ = (char)u; }
      else if (u < 0x20) q += sprintf(q, "\\u%04x", u);
      else *q++ = (char)u;
    }
    q += sprintf(q, "\"}");
    reply(s, 200, "application/json", o, (size_t)(q - o));
    free(o);
  }
  if (r) SherpaOnnxDestroyOfflineRecognizerResult(r);
  SherpaOnnxDestroyOfflineStream(st);
  free(pcm);
}

/* Case-insensitive prefix test for a header line. */
static int has_prefix(const char *l, const char *p) {
  for (; *p; l++, p++)
    if (*l == 0 || *l == '\r' || (*l | 0x20) != *p) return 0;
  return 1;
}

static void handle(sock_t s) {
  static char buf[MAX_UPLOAD + 8192];
  size_t got = 0;
  char *body = NULL;
  long want = -1;
  for (;;) {
    int k = recv(s, buf + got, (int)(sizeof buf - 1 - got), 0);
    if (k <= 0) return;
    got += (size_t)k;
    buf[got] = 0;
    if (body == NULL) {
      char *e = strstr(buf, "\r\n\r\n");
      if (e == NULL) { if (got >= sizeof buf - 1) return; continue; }
      body = e + 4;
      want = 0;
      for (char *l = buf; l < e; l = strstr(l, "\r\n") + 2) /* every line ends in \r\n up to e */
        if (has_prefix(l, "content-length:")) want = atol(l + 15);
      if (want < 0 || want > MAX_UPLOAD) { reply_error(s, 400, "request too large"); return; }
    }
    if ((long)(got - (size_t)(body - buf)) >= want) break;
  }
  body[want] = 0;
  body[-4] = 0; /* from here on buf is the request line and headers only, never the audio */
  if (strncmp(buf, "GET /health", 11) == 0) {
    char b[256];
    int n = snprintf(b, sizeof b, "{\"ok\": true, \"token\": \"%s\", \"voices\": %d, \"stt\": \"%s\"}", token, num_voices, (const char *)stt_state);
    reply(s, 200, "application/json", b, (size_t)n);
    return;
  }
  int to_speak = strstr(buf, "/audio/speech ") != NULL, to_hear = strstr(buf, "/audio/transcriptions ") != NULL;
  if (strncmp(buf, "POST ", 5) == 0 && (to_speak || to_hear)) {
    if (token[0]) {
      char want_auth[200];
      snprintf(want_auth, sizeof want_auth, "Bearer %s", token); /* the last header has no \r\n left */
      char *at = strstr(buf, want_auth);
      if (at == NULL || (at[strlen(want_auth)] != '\r' && at[strlen(want_auth)] != 0)) { reply_error(s, 401, "wrong token"); return; }
    }
    if (to_speak) {
      if (want > MAX_BODY) { reply_error(s, 400, "request too large"); return; }
      speak(s, body);
    } else {
      transcribe(s, body, (size_t)want);
    }
    return;
  }
  reply_error(s, 404, "not found");
}

static const char *arg(int argc, char **argv, const char *name, const char *def) {
  for (int i = 1; i + 1 < argc; i++)
    if (strcmp(argv[i], name) == 0) return argv[i + 1];
  return def;
}

int main(int argc, char **argv) {
  const char *dir = arg(argc, argv, "--dir", ".");
  int port = atoi(arg(argc, argv, "--port", "18431"));
  snprintf(token, sizeof token, "%s", arg(argc, argv, "--token", ""));
  long parent = atol(arg(argc, argv, "--parent-pid", "0"));
  int threads = atoi(arg(argc, argv, "--threads", "4"));
  if (parent > 0) start_watch(parent);
  /* Below the game's priority, so speaking never takes a frame away from it. */
#ifdef _WIN32
  SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
#else
  if (nice(5) == -1) { /* not allowed: speak at normal priority */ }
#endif

  char model[1024], voices[1024], tokens[1024], data[1024];
  snprintf(model, sizeof model, "%s/model.onnx", dir);
  snprintf(voices, sizeof voices, "%s/voices.bin", dir);
  snprintf(tokens, sizeof tokens, "%s/tokens.txt", dir);
  snprintf(data, sizeof data, "%s/espeak-ng-data", dir);
  SherpaOnnxOfflineTtsConfig cfg;
  memset(&cfg, 0, sizeof cfg);
  cfg.model.kokoro.model = model;
  cfg.model.kokoro.voices = voices;
  cfg.model.kokoro.tokens = tokens;
  cfg.model.kokoro.data_dir = data;
  cfg.model.kokoro.length_scale = 1.0f;
  cfg.model.kokoro.lang = "en";
  cfg.model.num_threads = threads > 0 ? threads : 4;
  cfg.model.provider = "cpu";
  cfg.max_num_sentences = 1;
  cfg.silence_scale = 0.2f;
  /* Speech to text loads beside the voices, so speaking is ready first. */
  snprintf(stt_dir, sizeof stt_dir, "%s/stt", dir);
  char probe[1100];
  snprintf(probe, sizeof probe, "%s/encoder.int8.onnx", stt_dir);
  FILE *pf = fopen(probe, "rb");
  if (pf) {
    fclose(pf);
    stt_threads = cfg.model.num_threads;
    stt_state = "loading";
    start_stt();
  }
  /* The voices are optional when speech to text is there (the installer has both as options). */
  FILE *mf = fopen(model, "rb");
  if (mf) {
    fclose(mf);
    tts = SherpaOnnxCreateOfflineTts(&cfg);
  }
  if (tts == NULL && strcmp((const char *)stt_state, "none") == 0) { fprintf(stderr, "voice_server: could not load the voices in %s\n", dir); return 2; }
  num_voices = tts ? SherpaOnnxOfflineTtsNumSpeakers(tts) : 0;

#ifdef _WIN32
  WSADATA w;
  WSAStartup(MAKEWORD(2, 2), &w);
#else
  signal(SIGPIPE, SIG_IGN);
#endif
  sock_t ls = socket(AF_INET, SOCK_STREAM, 0);
  struct sockaddr_in a;
  memset(&a, 0, sizeof a);
  a.sin_family = AF_INET;
  a.sin_port = htons((unsigned short)port);
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (ls == INVALID_SOCKET || bind(ls, (struct sockaddr *)&a, sizeof a) != 0 || listen(ls, 16) != 0) {
    fprintf(stderr, "voice_server: port %d is taken\n", port);
    return 3;
  }
  fprintf(stderr, "voice_server: %d voices on 127.0.0.1:%d\n", num_voices, port);
  for (;;) {
    sock_t c = accept(ls, NULL, NULL);
    if (c == INVALID_SOCKET) continue;
#ifdef _WIN32
    DWORD tv = 5000;
#else
    struct timeval tv = {5, 0};
#endif
    setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, (const char *)&tv, sizeof tv); /* a silent client can't stall us */
    handle(c);
    CLOSESOCK(c);
  }
}
