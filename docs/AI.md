# AI-driven people

Every person in every settlement has a name, a job, personality traits, likes, worries, a
home, a daily routine, and a memory of you. All of it is saved with the world: if you
insult the blacksmith on day 3, they still remember it on day 300, and people who die stay
dead.

People work at three levels, and each one falls back to the one below it:

1. **Conversation** (press E on someone). With a language model configured, the person
   answers in character. They know their own story, the time of day, rumours in their
   settlement and what they remember about you. Their reply can change their mood, their
   opinion of you and their goals, and it can make them act: follow you, go home, flee,
   attack, open trade, give or lend you Marks, hand you a gift, and do things with their
   body: wave, nod, wink, dance, sit, jump, point, hold up any fingers, and dozens more.
   Without a model they use built-in, keyword-driven dialogue that understands the same
   requests ("can you hold up three fingers?", "could you spare some Marks?"). Its lines
   (NPCTalk) are composed per person: each has their own way of addressing you, a pet
   phrase and a temper (gruff, warm, timid, greedy, curious; children talk like children),
   speaks in their culture's voice (medieval folk, frontier spacers, Sylvari or Vex; human
   worlds never hear of glowing or magic things), reacts to dozens of topics, to insults
   and compliments, turns the talk to their own worries, neighbours and the town's news,
   remembers what you last talked about, and avoids repeating what they said lately.
2. **Background thinking.** Now and then a person near you asks the model what they want
   to do next ("go to the market", "avoid the stranger"). This is optional and rate-limited.
3. **Fast decisions.** Every couple of seconds each person picks an action: work, wander,
   socialise, go home, sleep, greet, follow, flee, confront, attack, trade, dance, sit or
   gift. The built-in utility AI decides from the hour, their traits, their energy, how they
   feel about you and whether you are armed: sociable people dance in the square in the
   evening (every seventh day is a festival), the tired and the old sit on a stool, friends
   bring you a present once a day, guards salute, the wary point and shake a fist. You can
   replace it with your own decision service (below).

## Money, gifts, loans and gear

Everyone carries a purse of Marks and a few goods from their trade, and wears what they
own: guards start in their era's armour. In a conversation:

- **Trade** works with anyone. Villagers sell what their work makes and pay out of their
  own purse; greedy people charge more and friends get better prices.
- **Give** hands them Marks or anything you carry. Armour is put on and shows on their
  body, a weapon or tool goes in their hand, food gets eaten. Gifts raise their opinion of
  you, more so for things they like.
- **Ask** lists things to ask for (wave, dance, hold up fingers, play dead, spare some
  Marks...). Asking goes through the same conversation, so they decide by personality.
- **Loans**: someone who lends you Marks expects them back within three days. Paying them
  (Give) settles the debt first; once it is overdue they remind you and like you less.

## Voices

People speak their lines aloud (Settings > AI > Spoken voices), each with a voice of their
own. There are three engines:

| Engine | How it sounds | What to set |
|---|---|---|
| **Built-in natural voices** (the default) | Human-sounding neural voices ([Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), Apache-2.0) that come with the game and run offline. 128 voices, each a mix of Kokoro's own, handed out so neighbours sound different; children, teens and old folk sound their age; regional accents in the old lands (southern English, Northern, Midlands, Scottish, and received pronunciation for clergy and gentry) and on the frontier (American, New York, Caribbean, British). | Nothing. The game starts its voice program (`voices/` beside the game, source in `tools/voice_server`) in the background. |
| **Natural voices** | Like real people, with an accent and manner per person (West Country, Scottish, Irish, Welsh in the old worlds; Australian, Californian, London... in the sci-fi one), heard from where they stand. | **Voice server**: OpenAI (`gpt-4o-mini-tts`, uses your OpenAI key automatically when OpenAI is the provider) or a free local [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI) / [speaches](https://github.com/speaches-ai/speaches) server, e.g. `http://127.0.0.1:8880/v1`. Kokoro gives British voices in the old worlds and a mix in the sci-fi one. |
| **This PC's voices** | The operating system's speech voices. Works offline, but sounds robotic unless you have "Natural", "Neural", "Enhanced" or "Premium" voices installed (they are preferred automatically). | Nothing. |

With **Voice engine** on Automatic, a voice server is used whenever one is set and answering,
the built-in voices otherwise, and this PC's voices only if neither works. **Test voice** plays a sample.

### Talking with your own voice

Hold **B** while looking at someone, or inside a conversation (press **Enter** to type
instead), or hold **Hold to speak**. The button shows your microphone level while you talk;
if only silence comes in, the conversation says so, and which input device is in use. The
recording becomes text through:

| Setup | What to set |
|---|---|
| Nothing (the default) | The built-in speech recognition that comes with the game (installer option **Talk with your voice**, about 660 MB): NVIDIA's Parakeet TDT 0.6B v2 model, run offline by the built-in voice program (`tools/voice_server`, `POST /v1/audio/transcriptions`). |
| OpenAI provider, without the built-in one | It uses the same key, with `gpt-4o-mini-transcribe`. |
| **Speech-to-text server** set | Any OpenAI-compatible `/audio/transcriptions` server, e.g. a local speaches or LocalAI at `http://127.0.0.1:8000/v1`, or `https://api.openai.com/v1` with a key. It comes first; the built-in one takes over if it fails. |
| None of these, on Windows | Windows' own offline speech recogniser. Less accurate; the last fallback. |

Local chat servers (Strata, Ollama, LM Studio) and the Anthropic API can't turn speech into
text, so they are never asked.

### Open mic

Turn on **Open mic** in Settings > AI, or press **O** (rebindable). The microphone stays
on and the game listens for phrases (it pauses while people in the game are speaking, so it
never hears its own voices; headphones still help). A tag at the top right shows it is on.

- In a conversation, what you say is your reply.
- Out loud near people ("Hey, can anyone spare me 5 marks?"), everyone within about 14 m
  hears it, but only one answers: the person you face, otherwise the nearest one whose quick
  answer would be yes (or who has an answer to your question). Everyone else ignores you, so
  voices never pile up. Talk that isn't meant for anyone (no question, greeting or request)
  draws no answer.
- Whoever answers comes over and keeps talking with you hands-free, without the
  conversation window, until about 25 seconds of quiet or you walk away. Pressing **E** on
  them opens the window with the conversation so far.

**Test microphone (3 s)** in Settings > AI records you and shows what was understood.

### Quick replies

With an AI provider, a reply takes a moment, so people first answer straight away from a
fixed list with a fitting gesture: "Yes." (nod), "No." (head shake), "Hmm, let me think
about that." (thinking pose), "Maybe.", a greeting, "You're welcome.", "Excuse me?"... or
nothing, and just wait. The model's full answer follows on from it. Requests use the same
rules as the built-in dialogue, so a quick "Yes" is something they will actually do.

The fast decision service (below) can make the pick: alongside its usual batches it
receives `{"version": 1, "kind": "interject", "said": "...", "suggested": "think",
"options": ["yes", "no", "think", "maybe", "greet", "thanks", "surprised", "offended", "none"],
"lines": {"yes": "Aye.", ...}, "npc": {...}}` and answers `{"pick": "think"}` within 0.8 s,
or anything else to keep the suggested pick. Turn it off with **Quick replies**.

## Choosing a model

Open **Settings > AI** and pick a provider:

| Provider | What you need |
|---|---|
| Off | Nothing. Built-in dialogue and decisions. |
| Strata (local) | A Strata server on `http://127.0.0.1:8080/v1`. |
| Ollama (local) | [Ollama](https://ollama.com) running, with a model pulled (e.g. `ollama pull llama3.1:8b`). |
| LM Studio (local) | LM Studio's local server started. |
| Anthropic Claude API | An API key from console.anthropic.com. Default model `claude-haiku-5-5`. |
| OpenAI API | An API key from platform.openai.com. Default model `gpt-5-mini`. |
| OpenRouter | An OpenRouter key. |
| Custom | Any OpenAI-compatible server (llama.cpp, vLLM, text-generation-webui, ...). |

Press **Test connection** to check it. The API key is stored encrypted in `ai.cfg` in the
save folder, keyed to this machine.

A ChatGPT (or Claude.ai) chat subscription cannot be used: those subscriptions do not come
with API access. Use an API key or a local model.

**Cost control.** `Max model requests per minute` is a hard cap (default 12). Background thinking
only uses spare budget and can be turned off. Conversations use one request per line you
say.

## Wire formats

- `openai`: `POST {base}/chat/completions` with `Authorization: Bearer <key>`. When
  "Ask for JSON replies" is on, the request asks for `response_format: {"type": "json_object"}`;
  turn it off for servers that reject that field.
- `anthropic`: `POST {base}/messages` with `x-api-key` and `anthropic-version: 2023-06-01`.

The model is asked to reply with JSON:

```json
{"say": "...", "mood": "calm", "action": "none", "do": "wave", "marks": 0, "rel_change": 0,
 "remember": "...", "goal": "...", "options": ["...", "..."]}
```

`action` is one of `none, follow, stop_following, trade, go_home, flee, attack, leave,
give_money, lend_money, gift, ask_repay`. `marks` is how many Marks a `give_money` or
`lend_money` hands over (capped by their purse and nature). `do` is something they do
with their body right now: a full-body action (`dance, sit, stand, jump, crouch, kneel,
roll, flip, eat, throw, phone, zombie, play_dead, cast, block, punch, combo, push, yes, no,
fold_arms, spar, pick_up, hand_over, lantern`) or a gesture (`wave, wave_both, point,
thumbs_up, thumbs_down, fist, salute, beckon, stop, shrug, clap, cheer, facepalm, think,
pray, hips, peace, rock, ok, call_me, crossed, count, bow, nod, shake_head, tilt, wink,
wink_r, fingers_1..fingers_5, finger_thumb, finger_index, finger_middle, finger_ring,
finger_pinky`). Unknown values are ignored. `rel_change` is clamped to ±10 per line. If a model replies in plain text instead, the text
is used as the spoken line and nothing else changes.

## Your own decision service

Set **Fast decision service URL** (and optionally a key, sent as `Authorization: Bearer`). Every two
seconds the game posts the people near you:

```json
{
  "version": 1,
  "context": {"hour": 14.5, "day": 12, "player": {"x": 210.4, "z": -88.0, "health": 100}},
  "actions": ["idle", "wander", "work", "socialize", "go_home", "sleep", "greet",
              "follow", "flee", "confront", "attack", "trade", "dance", "sit", "gift"],
  "npcs": [
    {"id": "3_-2_4", "name": "Edda Thorne", "job": "farmer", "era": "Medieval",
     "traits": {"friendly": 0.7, "brave": 0.4, "curious": 0.5, "diligent": 0.8, "greedy": 0.2},
     "rel": 5, "mood": "calm", "energy": 0.62, "hp": 100, "hour": 14.5,
     "player_dist": 12.3, "player_armed": false, "player_wanted": 0, "goal": "", "current": "work"}
  ]
}
```

Reply within the timeout (default 1.5 s) with:

```json
{"decisions": [{"id": "3_-2_4", "action": "greet", "seconds": 20, "say": "Morning!"}]}
```

`player_wanted` is the player's wanted level (0 to 5 stars) in that person's settlement:
the built-in engine sends guards to confront a wanted player and to attack from 3 stars.

`seconds` (optional) holds the action that long; `say` (optional) is shown above their head.
People you leave out, unknown actions, slow replies and errors all fall back to the built-in
engine, so the service can be as small or partial as you like. It is a good fit for a fast
learned policy (a JEPA-style world model, a small classifier) sitting beside a slower
language model that handles conversation.

`tests/mock_llm.py` is a tiny reference server for all three endpoints.
