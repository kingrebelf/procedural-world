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
   requests ("can you hold up three fingers?", "could you spare some Marks?").
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

People speak their lines aloud with your PC's built-in text-to-speech voices (Settings >
AI > Spoken voices). Each person keeps a voice that suits them, with pitch and pace from
their age, temperament and mood. Nothing leaves your PC.

To talk with your own voice, hold **B** while looking at someone (or hold **Hold to speak**
in the conversation window). The recording is turned into text by a speech-to-text server:

| Setup | What to set |
|---|---|
| OpenAI provider | Nothing: it uses the same key, with `gpt-4o-mini-transcribe`. |
| Local (Ollama, LM Studio, Anthropic...) | **Speech-to-text server**: any OpenAI-compatible `/audio/transcriptions` server, e.g. a local [speaches](https://github.com/speaches-ai/speaches) or LocalAI at `http://127.0.0.1:8000/v1`, or `https://api.openai.com/v1` with a key. |

The Anthropic API has no speech-to-text, so with Claude as the provider set a separate
speech-to-text server.

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
     "player_dist": 12.3, "player_armed": false, "goal": "", "current": "work"}
  ]
}
```

Reply within the timeout (default 1.5 s) with:

```json
{"decisions": [{"id": "3_-2_4", "action": "greet", "seconds": 20, "say": "Morning!"}]}
```

`seconds` (optional) holds the action that long; `say` (optional) is shown above their head.
People you leave out, unknown actions, slow replies and errors all fall back to the built-in
engine, so the service can be as small or partial as you like. It is a good fit for a fast
learned policy (a JEPA-style world model, a small classifier) sitting beside a slower
language model that handles conversation.

`tests/mock_llm.py` is a tiny reference server for all three endpoints.
