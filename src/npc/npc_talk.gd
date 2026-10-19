class_name NPCTalk
## The built-in voice of the people: what they say when no language model is connected,
## and the barks they call out even when one is. Lines are composed from parts (an
## opener, a body, a turn to their own concerns, a pet phrase) and fitted to who is
## talking: their culture (medieval folk, frontier spacers, the fey Sylvari or the alien
## Vex), their temper, age, job, mood, what they are doing, how well they know you and
## the hour. Each person keeps stable verbal habits (how they address you, a pet phrase,
## a filler word) drawn from their id, and remembers the last few things they said
## (rec["_said"], a short ring of hashes) so they don't repeat themselves.
##
## Templates use {placeholders}, filled by fill(): {a} is how they address you (", friend"
## or nothing), {first} their first name, {town}, {likes}, {worry}, {job}, {doing} (their
## current duty), {ruler}, {drink}, {gods}, {beast}, {inn}, {trader}, {n1}/{n1job} (a
## neighbour), {rumor}, {day}, {age}, {w} (a word the traveller used).
##
## Human worlds (Eras.theme "human") never hear of glowing things, magic or fey folk:
## only the "fey" and "vex" banks may mention them, and those cultures exist only on
## alien and old mixed worlds.

const SAID_MAX := 8

## Words that differ by culture.
const VOCAB := {
	"old": {"ruler": "the king", "drink": "ale", "gods": "the gods", "beast": "wolves", "inn": "the tavern"},
	"fey": {"ruler": "the Grove Mother", "drink": "honeywine", "gods": "the old powers", "beast": "the thornbacks", "inn": "the mead hall"},
	"frontier": {"ruler": "the Company", "drink": "rotgut", "gods": "whoever's listening up there", "beast": "raiders", "inn": "the cantina"},
	"vex": {"ruler": "the Spire-council", "drink": "brine-tea", "gods": "the Lattice", "beast": "the ferals", "inn": "the cantina"},
}

## How they address someone they don't know, and someone they like.
const ADDR := {
	"old": {"far": ["stranger", "traveller", "friend", "wayfarer", "stranger"], "near": ["friend", "my friend", "neighbour", "old friend"],
		"warm": ["love", "my dear", "dear heart", "pet"]},
	"fey": {"far": ["wanderer", "stranger", "far-walker", "friend"], "near": ["friend", "sapling", "heart-friend", "dear one"],
		"warm": ["little sapling", "dear one", "bright heart"]},
	"frontier": {"far": ["stranger", "friend", "pal", "drifter", "chief", "boss"], "near": ["friend", "pal", "partner", "buddy"],
		"warm": ["hon", "sweetheart", "kid"]},
	"vex": {"far": ["outworlder", "visitor", "human", "guest"], "near": ["friend-human", "companion", "guest-friend"],
		"warm": ["small friend", "dear guest"]},
}

## Pet phrases: a closing sentence each person is fond of.
const PET := {
	"old": ["Mark my words.", "That's the truth of it.", "Fair's fair.", "Or so I reckon.", "Gods' honest truth.",
		"Not that anyone asks me.", "And there's an end to it.", "Sure as rain.", "You can take that to the miller.", "Saints preserve us."],
	"fey": ["So the leaves say.", "As the roots remember.", "Mark the wind.", "So it has always been.", "The wood keeps no secrets.",
		"By moon and mere.", "Soft now.", "Hear it, if you can."],
	"frontier": ["No lie.", "Hand to heart.", "Straight up.", "For what it's worth.", "Don't quote me.", "That's the long and short of it.",
		"Ask anyone.", "Swear on my last ration.", "Just saying.", "Write that down."],
	"vex": ["This is calculated.", "The Lattice notes it.", "A curious datum.", "So the Spire records.", "Precisely so.",
		"It is known.", "Your kind would say, obviously.", "I have counted it twice."],
	"child": ["Honest!", "Cross my heart.", "That's what my mum says.", "It's true!", "I'm not making it up."],
	"elder": ["In my day, things were different.", "Mark an old head's words.", "I've seen it all before.", "These old bones know."],
}

## Filler tucked into the end of a sentence ("Busy day, mind you.").
const FILLER := {
	"old": ["mind you", "I'll grant you", "and no mistake", "like as not", "I dare say"],
	"fey": ["I think", "or near enough", "if the wind allows", "so to speak"],
	"frontier": ["honestly", "far as I can tell", "give or take", "more or less", "y'know"],
	"vex": ["approximately", "as you would say", "by our reckoning", "within tolerance"],
	"child": ["I think", "probably", "maybe"],
}

## Words that start a sentence ("Well, ...").
const LEAD := {
	"old": ["Well,", "Now then,", "Ah,", "Look here,", "Aye, well,"],
	"fey": ["Ah,", "Listen,", "Hush,", "Oh,"],
	"frontier": ["Look,", "Listen,", "Okay,", "Right,", "So,"],
	"vex": ["Observe,", "Attend,", "So,", "Hm,"],
	"child": ["Um,", "So,", "Oh,"],
}

## A short first sentence by temper.
const OPENER := {
	"gruff": ["Hm.", "What now?", "Make it quick.", "Huh.", "Right."],
	"warm": ["Oh, now.", "Ha!", "Well, well.", "Oh!"],
	"timid": ["Oh! Um.", "Oh. Sorry.", "Er.", "Um, well."],
	"greedy": ["Hm, hm.", "Now then.", "Ah."],
	"curious": ["Ooh.", "Oh?", "Huh!"],
	"plain": ["Hm.", "Well.", "Ah."],
	"child": ["Ooh!", "Whoa.", "Hey!"],
}
const MOOD_OPENER := {
	"angry": ["Hmph.", "Not now.", "What?"], "sad": ["Ah, well.", "Sorry, I'm not much company today."],
	"afraid": ["Oh! You startled me.", "Easy, easy."], "happy": ["Ha!", "Oh, good day for it!"],
}

# --- Greetings ---------------------------------------------------------------------------

## Greetings by the time of day: dawn, morning, midday, afternoon, evening, night.
const TIME_GREET := {
	"old": {
		"dawn": ["Up with the cockerel{a}?", "Early to be about{a}. Couldn't sleep either?", "Dawn's barely cracked{a}. What brings you out?"],
		"morning": ["Morning{a}.", "Good morning to you{a}.", "Fine morning for it{a}.", "Morning{a}. Mind the puddles by the well."],
		"midday": ["Afternoon near enough{a}.", "Sun's high{a}. You eaten yet?", "Good day{a}. Hot work, this time of day."],
		"afternoon": ["Good afternoon{a}.", "Afternoon{a}. Long day, isn't it?", "Day's getting on{a}."],
		"evening": ["Evening{a}.", "Good evening{a}. Lamps'll be lit soon.", "Evening{a}. Supper's on, somewhere."],
		"night": ["Late to be wandering{a}.", "Bit dark to be out{a}. Keep to the lit streets.", "Night{a}. Quiet, isn't it?"],
	},
	"fey": {
		"dawn": ["The dew's still waking{a}.", "You walk early, like the deer{a}.", "First light{a}. The birds have been gossiping about you."],
		"morning": ["Bright morning{a}.", "Good morrow{a}. The leaves are in a good mood today.", "Morning sits well on you{a}."],
		"midday": ["The sun is overhead{a}. Even the shade is drowsy.", "Midday{a}. The bees are loud about it."],
		"afternoon": ["The light leans long{a}.", "Good afternoon{a}. The wood is sleepy now."],
		"evening": ["The moths are rising{a}.", "Evening comes in soft{a}.", "Good even{a}. The mere is turning silver."],
		"night": ["The night is deep{a}. Walk where the moss shines.", "Owl-hours{a}. What keeps you waking?", "Hush. The wood is sleeping{a}."],
	},
	"frontier": {
		"dawn": ["You're up early{a}. Graveyard shift?", "Too early for this{a}. What's up?", "Sun's barely over the ridge{a}."],
		"morning": ["Morning{a}.", "Hey{a}. Coffee's on, if you can call it that.", "Morning{a}. Gate log says you're new."],
		"midday": ["Hey{a}. Hot one today.", "Midday{a}. Grab some shade.", "Hey there{a}. Lunch break, so make it quick."],
		"afternoon": ["Afternoon{a}.", "Hey{a}. Shift's half done.", "Afternoon{a}. Wind's picking up out there."],
		"evening": ["Evening{a}.", "Hey{a}. Shift's over, finally.", "Evening{a}. Lights on soon, power willing."],
		"night": ["Bit late for a walk{a}.", "Night shift, huh{a}?", "It's late{a}. Keep inside the perimeter."],
	},
	"vex": {
		"dawn": ["Your star is barely up{a}. You keep strange hours.", "Early cycle{a}. The hive is still quiet."],
		"morning": ["First shift greets you{a}.", "The morning cycle runs{a}. State your purpose.", "Morning{a}. You are a long way from your world."],
		"midday": ["The star is high{a}. Humans wilt in this heat, I am told.", "Midcycle{a}."],
		"afternoon": ["Late cycle{a}.", "The work-hours wane{a}."],
		"evening": ["The spires are lighting{a}.", "Dusk-shift{a}. The towers hum at this hour."],
		"night": ["Night cycle{a}. Humans should be resting.", "The dark hours{a}. Few walk them by choice."],
	},
}

## First meeting, by culture.
const FIRST_GREET := {
	"old": ["Haven't seen you before{a}.", "A new face. Don't get many of those.", "You're not from round here, are you{a}?",
		"Good day to you{a}. Passing through?", "Hello there{a}. Mind the mud.", "Well, look at you{a}. Come far?",
		"Welcome{a}. Wipe your boots, folk are particular here.", "Afternoon or morning, I've lost track. Hello{a}."],
	"fey": ["A new face beneath the old trees.", "Welcome, if you come in peace{a}.", "Light on your path{a}.",
		"The grove whispered you'd come.", "You smell of road dust and iron{a}. Welcome.", "Ah, a far-walker. Sit, if you like."],
	"frontier": ["New arrival{a}? Welcome to the frontier.", "Hey. Keep your weapon holstered and we'll get along.",
		"You're new{a}. Didn't see a shuttle come in.", "Hey there{a}. Signal's good today.", "Another drifter. Welcome to the edge of nowhere.",
		"Hey{a}. First time out this far?"],
	"vex": ["A human. We see few of your kind{a}.", "You came from the far roads{a}? Curious.", "Greetings{a}. Do not touch the conduits.",
		"Your face is soft{a}. Most human faces are, I find.", "Outworlder. You are permitted to speak.", "Welcome to the spires{a}. Mind the lattice-lines."],
	"child": ["Hi! Who are you?", "Are you an adventurer? You look like one.", "Mum says not to talk to strangers. You're not strange though, are you?",
		"Hello! Have you got a sword? Can I see it?", "Ooh, you're new! Where'd you come from?", "I've never seen you before. Are you lost?"],
}

## Coming back, by how they feel about you.
const BACK_GREET := {
	"old": {"fond": ["There you are{a}! Good to see you.", "Ah, it's you{a}. Come here, then.", "Back again{a}? Best news I've had all day.", "Look who it is{a}!"],
		"known": ["Ah, you again{a}.", "Back, are you{a}?", "Hello again{a}.", "Didn't expect to see you again so soon{a}."],
		"cold": ["You again.", "Oh. It's you.", "What is it this time?", "I'd hoped you'd moved on."]},
	"fey": {"fond": ["Heart-friend! The wood brought you back.", "There you are{a}. I hoped the path would turn you this way.", "Welcome home, for so it is now{a}."],
		"known": ["You return{a}, like the swallows.", "Ah, the far-walker again.", "Back beneath the boughs{a}?"],
		"cold": ["You. The roots remember you.", "The wind brings you back. Pity.", "Speak, then, and go."]},
	"frontier": {"fond": ["Hey{a}! Good to see you in one piece.", "There's my favourite drifter.", "Look who's back{a}. Pull up a crate."],
		"known": ["You again{a}. What's up?", "Back already{a}?", "Hey, it's you{a}."],
		"cold": ["You again. Great.", "Oh. Hey. I'm busy.", "What now?"]},
	"vex": {"fond": ["Friend-human! Your return is recorded with pleasure.", "You came back{a}. I had calculated you might."],
		"known": ["The human returns.", "You again{a}. Speak."], "cold": ["You. I remember you.", "Your presence is noted. Reluctantly."]},
	"child": {"fond": ["You came back! Did you bring me anything?", "Yay, it's you!"], "known": ["Oh, it's you again!", "Hi again!"],
		"cold": ["I'm not talking to you.", "Go away."]},
}

## Remembering what you last talked about ({topic}).
const RECALL := ["Still thinking about {topic}{a}?", "Been chewing over what you said about {topic}{a}.",
	"Last time it was {topic}. What is it today{a}?", "Ah, the one who asked about {topic}.", "Back again{a}? I've had more thoughts on {topic}, if you want them."]

## Greetings that say what they are busy with.
const BUSY_GREET := ["Can't stop long{a}, I'm {doing}.", "Mind me, I'm {doing}.", "Talk while I work{a}? I'm {doing}.",
	"You've caught me {doing}. Go on, then."]

## Greetings by temper (any culture).
const TONE_GREET := {
	"gruff": ["What do you want?", "Hm. You.", "If you're selling something, I'm not buying.", "Say your piece."],
	"warm": ["Oh, hello! Lovely to see a new face.", "Hello{a}! Come, come.", "Well, aren't you a welcome sight{a}."],
	"timid": ["Oh! Um, hello.", "H-hello. Can I help? I mean, do you need something?", "Sorry, I didn't see you there."],
	"greedy": ["Hello{a}. Got coin, have you?", "Ah, a customer, perhaps?", "Welcome{a}. Everything's for sale, if the price is right."],
	"curious": ["Oh, who are you, then?", "Hello{a}! Where've you come from? Tell me everything.", "A new face! What's your story?"],
}

## Greetings by job.
const JOB_GREET := {
	"guard": ["Keep the peace and we'll get on fine{a}.", "Eyes front{a}. What's your business?", "Weapons sheathed in town{a}."],
	"warden": ["Walk softly here{a}. The wood is listening.", "The paths are watched{a}. Mind them."],
	"security officer": ["ID's not required, but good behaviour is{a}.", "Keep it holstered and we're friends{a}."],
	"farmer": ["Mind the furrows{a}.", "Don't step on the turnips{a}.", "Fine day for growing{a}."],
	"smith": ["Careful, the iron's hot{a}.", "Need something mended{a}?"],
	"innkeeper": ["Thirsty{a}? Come in, come in.", "There's a stool with your name on it{a}."],
	"hunter": ["Quiet now{a}. Fresh tracks about.", "You walk loud for someone in the woods{a}."],
	"priest": ["Blessings on you{a}.", "Peace be with you{a}.", "The gods see you, child."],
	"bard": ["A new audience! Hello{a}.", "Ah, a face for a song{a}."],
	"beekeeper": ["Mind the bees{a}. They're cross today.", "Slowly now{a}. Bees don't like sudden folk."],
	"herbalist": ["You look peaky{a}. Need a tonic?", "Mind the feverfew{a}."],
	"medic": ["You look like you could use a check-up{a}.", "Any wounds? Cuts? Coughs?"],
	"scavenger": ["Got any scrap{a}? I buy scrap.", "Watch your step, there's sharp stuff everywhere."],
	"pilot": ["Skies are clear{a}. For now.", "You fly{a}? No? Pity."],
	"courier": ["Can't stop, deliveries! Hi{a}!", "Hey{a}. Package for you? No? Shame."],
	"data broker": ["Information's cheap today{a}. Well. Cheaper.", "I know things{a}. Want to know what I know?"],
	"engineer": ["Hey{a}. Don't touch anything with a warning light.", "Something rattling on you{a}? I fix rattles."],
	"trader": ["Come and see what I've got{a}.", "Best prices on the road{a}, I promise."],
	"fisher": ["Fish are biting today{a}.", "Mind the nets{a}."],
	"castaway": ["Water! Have you got water?", "Thank the stars, a living soul!"],
	"captain": ["Welcome aboard{a}. Mind my deck.", "On my ship, you keep out of the crew's way{a}."],
	"sailor": ["Ahoy{a}!", "Fair winds to you{a}."],
	"deckhand": ["Watch the ropes{a}!", "Mind your feet, the deck's wet."],
	"lookout": ["Saw you coming a mile off{a}.", "Ahoy below!"],
	"ship's cook": ["Hungry{a}? Don't tell the captain I fed you."],
	"pirate": ["Well, well. Fresh meat.", "Look what washed up."],
}

# --- Talk about things -----------------------------------------------------------------

## Turns of phrase used when the person moves the talk onto their own concerns.
const TURN_WORRY := ["What really keeps me up is {worry}.", "Truth be told, I've {worry} on my mind more than that.",
	"Me, I fret about {worry}.", "Mostly, though, I worry about {worry}.", "Anyway. Have you heard anything about {worry}?"]
const TURN_LIKES := ["Give me {likes} any day.", "Me, I'd sooner talk about {likes}.", "Nothing cheers me up like {likes}.",
	"If you want to get on my good side{a}, {likes} is the way."]
const TURN_ASK := {
	"old": ["What brings you to {town}, anyway?", "Where are you headed{a}?", "And you? What's your trade?", "Have you come far{a}?",
		"What do you make of the place?", "Got family somewhere{a}?", "Have you eaten? You look thin."],
	"fey": ["What road brought you here{a}?", "What do you seek, far-walker?", "And what does your heart want{a}?",
		"Have you walked beneath the old trees before?", "Tell me of your homeland. Is it green?"],
	"frontier": ["So what's your story{a}?", "Where are you headed?", "You working, or just passing?", "Where'd you come in from?",
		"You staying long, or just refuelling?", "What do you do, anyway?"],
	"vex": ["Tell me, what is your function?", "Why did you leave your world{a}?", "Do all humans ask so many questions?",
		"What is it like, to be so brief?", "Where does your road go after this?"],
	"child": ["Have you ever fought a monster?", "How old are you?", "Do you want to see my secret hideout? It's a secret.",
		"What's the biggest thing you've ever killed?", "Can I come with you?"],
}
const TURN_RUMOR := ["Here's a thing, though. {rumor}", "Did you hear? {rumor}", "Word going round is this. {rumor}",
	"You didn't hear it from me, but here's the news. {rumor}"]
const TURN_GOSSIP := ["Between us, {n1} the {n1job} has been in a mood all week.", "Have you met {n1}? The {n1job}. Good sort, mostly.",
	"{n1} the {n1job} owes me a favour. Don't tell them I said so.", "If you want to know anything, ask {n1}. Knows everyone's business.",
	"{n1} reckons the {n1job} trade's going to the dogs. {n1} always reckons that."]

## Gentle replies when they don't follow, before turning the talk.
const PUZZLED := {
	"old": ["Can't say I've an answer for that.", "That's beyond me{a}, I'm afraid.", "You've lost me there.", "Well, that's a new one.",
		"I'm a simple sort{a}. Say it plainer?", "Hah. If you say so.", "I'll have to sleep on that one."],
	"fey": ["Your words are like river stones. I turn them over and find nothing beneath.", "That is a riddle I cannot unknot{a}.",
		"Strange words. The wind will make sense of them, perhaps.", "I hear you, but I do not follow."],
	"frontier": ["Didn't catch that{a}.", "Not sure what you're getting at.", "That's above my pay grade.", "Huh. Okay.",
		"You lost me. Try again?", "Sure. Whatever you say{a}."],
	"vex": ["Your meaning does not parse{a}.", "I do not have a word for that.", "Human speech is so untidy.",
		"Explain, slowly. My translation is imperfect."],
	"child": ["Huh? What does that mean?", "That's a weird thing to say.", "I don't get it.", "You talk funny."],
}
const ECHO := ["\"{w}\", you say? Can't say I know much about {w}.", "{w}? Hah. Not something we talk about much here.",
	"{w}. Hm. My gran had views on {w}, but she's gone now."]

## Topics: words that bring them up, and what people say. Each topic has lines any
## culture can say ("all") and lines of its own.
const TOPICS := {
	"weather": {
		"all": ["Can't complain about the sky today{a}. Well, I could, but I won't.", "I don't trust a sky this calm.",
			"Weather's weather. It does what it likes.", "My knee says rain by nightfall. My knee's rarely wrong."],
		"old": ["Rain'd be welcome for the fields. Not for my roof.", "Turned cold last night. Had to fetch the extra blanket.",
			"Red sky this morning. Shepherds won't like it.", "If the wind turns east, mark it, there'll be a storm."],
		"fey": ["The clouds are dreaming today.", "The rain is a guest. We do not complain of guests.", "Listen. The wind has changed its song."],
		"frontier": ["Dust storm's due, if the forecast's worth anything. It isn't.", "Sensors say clear. Sensors lie.",
			"Hot enough to fry a circuit board out there."],
		"vex": ["Your weather is unruly. Ours is scheduled.", "The atmosphere is within tolerance. Barely."],
	},
	"food": {
		"all": ["Hungry{a}? {inn} does a fair supper.", "Haven't eaten since sunrise. Don't remind me.", "Food's the one thing nobody here argues about. Mostly."],
		"old": ["Bread and cheese, and an onion if you're lucky. Best meal there is.", "My mother's mutton stew. Nothing beats it.",
			"Harvest's been fair, so nobody's starving. Yet.", "Don't eat the innkeeper's pie on a Thursday. Trust me."],
		"fey": ["We eat what the wood offers. Berries, honey, roots, and sometimes a mushroom that makes you sing.", "Honeycake. If you've never had it, you have not lived."],
		"frontier": ["Rations again. Tastes like cardboard and regret.", "Hydroponics lettuce. Every. Single. Day.", "Fresh meat out here's worth more than fuel."],
		"vex": ["We take nourishment by schedule. Your kind eats when it pleases. Disordered.", "Human food is too soft. And it smells."],
		"child": ["I'm SO hungry. Have you got any sweets?", "I hate turnips. Do you hate turnips?"],
	},
	"drink": {
		"all": ["{inn}'s the place for {drink}. Don't let the landlord water it.", "A cup of {drink} and a quiet corner. That's all I ask of life.",
			"I'll drink to that. Later, mind. Work first."],
		"old": ["Ale's gone sour again. Don't tell the innkeeper I said so.", "I had three ales once and sang to a goat. We don't speak of it."],
		"fey": ["Honeywine is for feasts. Water is for wisdom.", "Drink from the mere, if you dare. It shows you things."],
		"frontier": ["Rotgut's cheap and it'll strip paint. So, perfect.", "The cantina waters the drinks. Everybody knows. Nobody cares."],
		"vex": ["Brine-tea sharpens the mind. You would hate it.", "Your drinks make humans loud. We have noticed."],
		"child": ["I'm not allowed ale. I had a sip once though.", "Do you like milk? I like milk."],
	},
	"family": {
		"all": ["Family's a blessing. Most days.", "Haven't seen my sister in years. She married far off.", "My folks are buried up on the hill. I still talk to them."],
		"old": ["Got three little ones and a wife who's cleverer than me. Don't tell her.", "My old dad was a {job} too. And his before him.",
			"My brother went off to be a soldier. Writes now and then. Badly."],
		"fey": ["My kin are the trees as much as the folk.", "My mother sang to the saplings. Now I do."],
		"frontier": ["My folks are back on the inner colonies. Haven't called in a year.", "Family? The crew here's the closest thing I've got."],
		"vex": ["We are hatched in clutches of forty. Family is a large word to us.", "My clutch-kin serve on three worlds."],
		"child": ["My mum's over there. Don't tell her I'm talking to you.", "My brother's annoying. Have you got a brother?"],
	},
	"romance": {
		"all": ["Ha! Who's asking?", "My heart's spoken for. Mostly.", "Love? Fickle thing. Like the weather, but costlier."],
		"old": ["The miller's girl smiled at me once. I still think about it.", "Courting's a lot of walking and not much else."],
		"fey": ["Love grows like ivy. Slowly, and then everywhere.", "I gave my heart to the moon once. It never gave it back."],
		"frontier": ["Romance out here is two people sharing a heater.", "Had someone once. They took the last shuttle out."],
		"vex": ["We pair for a cycle, then part. Your forevers puzzle us.", "Human courtship is very loud."],
		"child": ["Ew! Gross!", "Kissing is disgusting."],
	},
	"war": {
		"all": ["War? Gods keep it far from here.", "Every fight I ever saw was over something stupid.", "Rather plough a field than dig a grave."],
		"old": ["My uncle came back from the last war with one boot and no jokes.", "When {ruler} calls the levy, we all go. Don't have to like it.",
			"Soldiers came through last spring. Ate everything, paid for nothing."],
		"fey": ["The trees remember the last war. They grow crooked where the blood fell.", "We do not war. We wait. The wood outlasts everyone."],
		"frontier": ["Last war was over water rights. Next one'll be over power.", "I've seen what a pulse rifle does to a person. Never again."],
		"vex": ["The Vex do not war. We correct.", "Your species fights over very small things."],
		"child": ["I'm going to be a soldier when I'm big!", "Have you been in a battle? Did you win?"],
	},
	"monsters": {
		"all": ["Stay on the road after dark and you'll be fine. Probably.", "Something's been taking the chickens. Fox, I hope.", "I've seen tracks out past the fields the size of my hand."],
		"old": ["Wolves came down from the hills last winter. Took two sheep and a dog.", "Bandits are the real monsters, if you ask me.",
			"There's tales of a bear up the north ridge. Big as a cart."],
		"fey": ["The thornbacks walk at dusk. Do not meet their eyes.", "Not every shadow in the wood is a beast. Some are worse."],
		"frontier": ["Raiders are the worst of it. Worse than anything with teeth.", "Something big's been chewing the perimeter fence."],
		"vex": ["The ferals hunt beyond the lattice. Do not wander.", "Your kind calls everything it does not understand a monster."],
		"child": ["I saw a wolf once! It was THIS big.", "Are there monsters? Real ones? Have you killed one?"],
	},
	"gods": {
		"all": ["I say my prayers. Can't hurt.", "The priest says be good. I try. Mostly.", "If {gods} are watching, they're keeping it quiet."],
		"old": ["Gods keep us all, I say, and keep the taxman away.", "I go to the shrine at harvest. Never missed one.", "My gran swore by the old saints. I swear at them."],
		"fey": ["The old powers live in every root and stone. You need only listen.", "We do not pray. We listen, and sometimes we are answered."],
		"frontier": ["If anybody's up there, they're not taking calls.", "I believe in a full fuel tank and a working airlock."],
		"vex": ["The Lattice holds all. It does not need your belief.", "Your gods are very human. Have you noticed?"],
		"child": ["Do the gods see me when I steal biscuits?", "The priest is scary."],
	},
	"magic": {
		"old": ["Spells and wizards? That's minstrels' talk.", "Only tricks I've seen are a juggler at the fair. Good one, mind.",
			"If there were such things, I'd want one that weeds turnips."],
		"frontier": ["No such thing. There's tech you understand and tech you don't.", "Ha. Tell that one to the engineers."],
		"fey": ["Magic is only the world, listened to closely.", "The wild magic thins, these days. You feel it in the roots.", "Every leaf here holds a little light. Look."],
		"vex": ["What you call magic, we call physics you have not met.", "The Sylvari speak of magic. Their songs are only resonance."],
		"child": ["I can do a trick! Watch. Okay, it didn't work.", "Can you do tricks? Show me one!"],
	},
	"money": {
		"all": ["Money's tight. Always is.", "Prices keep going up and my purse keeps going down.", "Everyone wants {coin}. Nobody wants to pay them."],
		"old": ["Taxes again. {ruler}'s men came round last week.", "A fair price, that's all I ask. Hard to find these days.", "Salt's dearer than silver this year."],
		"fey": ["Coin is a human game. We play it because we must.", "The Grove Mother asks no tithe. Only respect."],
		"frontier": ["Company scrip's worth less every month.", "Credits, Marks, whatever. Never enough of them."],
		"vex": ["Your coins are crude, but we accept them.", "Value is a calculation. Yours are often wrong."],
		"child": ["I found a coin once! I'm saving it.", "Have you got money? Are you rich?"],
	},
	"ruler": {
		"all": ["{ruler}? Never met them. Pay their taxes, though.", "As long as {ruler} leaves us be, I've no complaints.", "Best not talk about {ruler} too loud{a}."],
		"old": ["The king's far off, and his reeve's close by. The reeve's the one to watch.", "Long live the king, I say. And may he lower the taxes.",
			"His lordship came through once. Fine horse. Didn't stop."],
		"fey": ["The Grove Mother is old as the first oak. She speaks rarely, and only truth.", "We are ruled by the seasons more than anyone."],
		"frontier": ["The Company owns the land, the water and the air. Charges for all three.", "Governor's a hundred light-hours away. Suits me."],
		"vex": ["The Spire-council decides. We comply. It is efficient.", "You have kings? How very... singular."],
		"child": ["Is the king real? Have you seen him?", "I'd be a good king. I'd make it always summer."],
	},
	"sea": {
		"all": ["The water gives and the water takes.", "Never learned to swim. Never will.", "I like the sea best from the shore."],
		"old": ["My cousin went to sea. Came back with a parrot and no teeth.", "Fishermen say the shoals are moving. Bad sign, that."],
		"fey": ["The mere remembers every face it has seen.", "The water spirits are moody this season."],
		"frontier": ["Ocean out here's half salt, half rust.", "Water's the most valuable thing on this rock. Don't waste it."],
		"vex": ["Your oceans are very wet. Ours were drained long ago.", "The Vex do not swim. We are too dense."],
		"child": ["I want to go on a big ship one day!", "I caught a fish once. It was this big. No, this big."],
	},
	"travel": {
		"all": ["The roads aren't what they were. Keep your wits about you.", "Never been more than a day's walk from home. Never needed to.",
			"Travel broadens the mind, they say. And empties the purse."],
		"old": ["The king's road's safe by day. By night, less so.", "Went to the city once. Too loud, too dear, too many people."],
		"fey": ["Every path in the wood leads somewhere. Not always where you meant.", "The far-walkers bring the world's news on their boots."],
		"frontier": ["Next outpost's a long haul. Fuel up first.", "Out past the array, the maps stop being right."],
		"vex": ["You walk the land as if it were nothing. Your kind is reckless.", "The lattice-lines hum when travellers pass. We feel it."],
		"child": ["Take me with you! Please? I'm good at walking.", "Have you been everywhere? What's it like?"],
	},
	"work": {
		"all": ["Work's work. Pays the bills, mostly.", "Busy, busy. No rest for anybody here.", "Honest work never hurt anyone. Well. My back."],
	},
	"howareyou": {
		"happy": ["Good, thanks for asking! Couldn't be better.", "Grand, actually. Grand.", "Can't complain. Wouldn't, today."],
		"sad": ["Not so good, truth be told.", "Been better. Been worse too, I suppose.", "Tired. Just tired."],
		"angry": ["Don't ask.", "How do you think?", "Worse now, thanks."],
		"afraid": ["Jumpy. Everyone's jumpy.", "I'll feel better when I'm indoors."],
		"calm": ["Well enough, thank you.", "Same as ever. You?", "Can't complain. Nobody listens anyway.", "Not bad. Tired, but not bad."],
		"tired": ["Dead on my feet, honestly.", "Bone-tired. Long day."],
	},
	"player": {
		"cold": ["What do I think of you? Not much.", "I think you're trouble, that's what.", "I'll tell you when I trust you."],
		"stranger": ["Don't know you well enough to say.", "You seem alright. Time will tell.", "You've an honest face. Mostly."],
		"fond": ["You're good company, you are.", "I like you. Don't let it go to your head.", "You're one of the good ones{a}."],
	},
	"age": {
		"all": ["{age}, give or take a winter.", "Old enough to know better. {age}, if you must know.", "{age}. Don't say I look it."],
		"child": ["I'm {age}! Nearly {age1}.", "{age}. How old are you? You look really old."],
	},
	"likes": {
		"all": ["Me? I'm partial to {likes}.", "{likes}. Can't get enough of it.", "Simple things. {likes}, mostly.", "You really want to know? {likes}. There."],
	},
	"worry": {
		"all": ["Since you ask, {worry}.", "{worry}. Keeps me up nights.", "Truth? {worry}. Nobody else seems bothered.", "What worries me is {worry}. And my knees."],
	},
	"stars": {
		"old": ["Other worlds? Up there? My granddad swore the stars were other suns. He drank, mind.", "The stars are for sailors and fortune-tellers. My feet stay on this world."],
		"frontier": ["The old company records say our people came down from the stars. Nobody's going back up.", "You can see a long way out here at night. Further than anyone will ever travel."],
		"fey": ["The stars are the wood's lanterns, hung too high to reach.", "Every star is a tale. None of them are roads."],
		"vex": ["We watch the stars. We do not go to them.", "The sky is a ceiling. The Vex accept it."],
		"child": ["Do you think there are people on the stars? I'm going to count them all.", "My friend says the stars are far away. How far is far?"],
	},
	"animals": {
		"all": ["Good dog's worth more than a bad neighbour.", "The cats here eat better than I do.", "Never trust a goat. They're plotting."],
		"frontier": ["Only animal out here's the station cat. She runs the place.", "Saw a real horse once. Big. Smelly. Beautiful."],
		"vex": ["Your animals are very hairy.", "We keep no beasts. They are untidy."],
		"child": ["I've got a puppy! Well, it's the neighbour's. But I feed it.", "Do you like dogs? I LOVE dogs."],
	},
	"health": {
		"all": ["Keep warm, eat well, and stay away from the coughing ones.", "If you're hurt, the healer's who you want. Not me.", "I've a bad back and a worse knee. Otherwise fit as a fiddle."],
		"frontier": ["Med bay's got stims if you're hurting.", "Radiation's the quiet killer out here. Wear your badge."],
		"fey": ["There is a moss for every ache, if you know where to look.", "Rest under an old oak. It draws out the hurt."],
		"vex": ["Human bodies break so easily. Be careful.", "Our medics can repair you. Mostly."],
	},
	"home": {
		"all": ["Home's the house with the leaky roof, over that way.", "It's not much, but it keeps the rain off.", "Home is where they let you in at night."],
		"frontier": ["Bunk's in hab two. Barely room to turn around.", "Home's a dome and a cot. Good enough."],
		"fey": ["I sleep in a hollow beneath the roots. It's warmer than it looks.", "Home is the grove. All of it."],
		"vex": ["I rest in the spire, with my clutch-kin.", "Home is a cell in the lattice. Efficient."],
	},
	"time": {
		"all": ["It's {time}, day {day} by my count.", "{time}, near enough. Day {day}, if you're keeping track.", "Day {day}. {time}. Time flies, doesn't it?"],
	},
	"history": {
		"all": ["There's ruins up on the hill. Older than anyone knows.", "My gran used to tell stories of the old days. Half of them were lies. The best half.",
			"This place was here long before me, and it'll be here after."],
		"old": ["They say a king's buried under the barrow on the ridge. Nobody's dug to check.", "The old keep fell in my grandfather's time. Fire, they say."],
		"fey": ["The first trees were planted by the first singers. Or so the songs say.", "Before the iron-folk came, there were only the groves."],
		"frontier": ["The first colony ship landed a hundred years back. Half of them didn't make it.", "The old-world ruins are full of tech nobody can fix."],
		"vex": ["Our records go back eleven thousand cycles. Yours?", "The spires were grown, not built. Long ago."],
	},
	"joke": {
		"old": ["Why did the farmer win a prize? He was outstanding in his field. I'll be here all week.",
			"What's brown and sounds like a bell? Dung. Sorry. My dad's joke.", "A priest, a pig and a tax collector walk into a tavern. Only the pig pays."],
		"fey": ["Why did the oak blush? It saw the mere bathing. We find that very funny.", "A hedgehog asked the moon for a kiss. That is the whole joke. Children love it."],
		"frontier": ["How many engineers does it take to fix a hab light? None. That's a hardware problem.",
			"Why did the courier cross the dead zone? Somebody forgot to pay for express.", "I'd tell you a joke about the airlock, but you'd be blown away."],
		"vex": ["A human, a Sylvari and a Vex set out for the spires. Only the Vex arrives on time. That is our joke.", "We have one joke. It is about entropy. You would not laugh."],
		"child": ["Knock knock! You're supposed to say who's there.", "Why did the chicken cross the road? To get away from my brother!"],
	},
	"help": {
		"all": ["Depends what you need{a}. Coin, I've little. Advice, I've plenty.", "Help how? Say it plain and I'll see.", "If it's directions, ask. If it's money, ask nicely."],
	},
	"directions": {
		"all": ["The square's the middle of everything. Start there.", "Follow the road and you can't miss it.", "Ask at the stall{a}. {trader} knows where everything is.",
			"Over yonder, past the well. Can't miss it."],
		"frontier": ["Check the signposts. They're mostly right.", "Head for the comms tower and turn left. Probably."],
		"vex": ["Follow the lattice-lines. They go everywhere worth going.", "Directions are on every spire. You cannot read them? Hm."],
	},
	"yesno": {
		"all": ["Fair enough.", "Well, there you are, then.", "Right you are.", "Hah. Good.", "Glad we agree{a}."],
		"frontier": ["Copy that.", "Fair.", "Okay then."],
		"vex": ["Acknowledged.", "Noted."],
	},
}

## Which words bring up which topic, checked in order.
const TOPIC_WORDS := [
	["howareyou", ["how are you", "how's it going", "how do you do", "how are things", "how have you been", "you alright", "how goes it", "how you doing", "how's life", "are you happy", "are you ok", "are you okay", "are you well", "are you sad", "how do you feel", "how's your day", "you look tired"]],
	["player", ["about me", "of me", "think of me", "like me", "remember me", "who am i", "do you know me", "trust me"]],
	["age", ["how old", "your age"]],
	["likes", ["what do you like", "favourite", "favorite", "enjoy", "hobby", "hobbies", "free time", "for fun"]],
	["worry", ["worried", "worry", "worries", "afraid of", "scared of", "what's wrong", "problem", "trouble"]],
	["joke", ["joke", "funny", "make me laugh", "riddle", "jest"]],
	["romance", ["sweetheart", "romance", "kiss", "marry", "married", "lover", "girlfriend", "boyfriend", "single", "in love"]],
	["family", ["family", "wife", "husband", "children", "kids", "son", "daughter", "mother", "father", "mum", "mom", "dad", "brother", "sister", "parents"]],
	["stars", ["portal", "portals", "other world", "other worlds", "space", "planet", "planets", "stars", "star", "moon"]],
	["magic", ["magic", "spell", "spells", "wizard", "witch", "sorcery", "enchant", "enchanted", "fairy", "fairies", "elf", "elves", "glow", "glowing"]],
	["gods", ["god", "gods", "pray", "prayer", "faith", "temple", "church", "heaven", "divine", "religion", "holy", "saints"]],
	["war", ["war", "wars", "battle", "army", "soldier", "soldiers", "enemy", "invasion", "siege"]],
	["monsters", ["monster", "monsters", "beast", "beasts", "wolf", "wolves", "dragon", "creature", "creatures", "bandit", "bandits", "raider", "raiders", "danger", "dangerous", "ghost", "ghosts", "bear"]],
	["ruler", ["king", "queen", "lord", "lady", "prince", "princess", "ruler", "crown", "baron", "duke", "governor", "mayor", "council", "company", "emperor"]],
	["sea", ["sea", "ship", "ships", "boat", "boats", "sail", "sailing", "ocean", "harbour", "harbor", "port", "waves", "pirate", "pirates", "fishing", "swim"]],
	["drink", ["drink", "ale", "beer", "wine", "mead", "thirsty", "pub", "drunk", "booze"]],
	["food", ["food", "eat", "hungry", "bread", "meat", "cook", "meal", "dinner", "supper", "breakfast", "lunch", "starving", "stew", "cheese"]],
	["weather", ["weather", "rain", "raining", "snow", "snowing", "sunny", "storm", "wind", "windy", "cold", "hot", "fog", "cloud", "clouds", "sky"]],
	["money", ["money", "gold", "rich", "poor", "price", "prices", "tax", "taxes", "cost", "wage", "wages", "coin", "coins", "cheap", "expensive", "silver"]],
	["animals", ["horse", "horses", "dog", "dogs", "cat", "cats", "cow", "cows", "sheep", "pig", "pigs", "chicken", "chickens", "animal", "animals", "goat"]],
	["health", ["sick", "ill", "hurt", "wound", "wounded", "injured", "healer", "medicine", "doctor", "plague", "fever", "heal"]],
	["history", ["history", "old days", "ruins", "ancient", "long ago", "legend", "legends", "tale", "tales", "story"]],
	["time", ["what time", "the time", "time is it", "what hour", "what day", "which day", "today", "tonight"]],
	["travel", ["travel", "journey", "road", "roads", "adventure", "explore", "world", "abroad", "wander", "been to"]],
	["home", ["home", "house", "live", "sleep", "bed"]],
	["help", ["help"]],
]
## The words to name a topic in memory ("Talked with the traveller about the weather.").
const TOPIC_NAMES := {"weather": "the weather", "food": "food", "drink": "drink", "family": "family", "romance": "love",
	"war": "war", "monsters": "the dangers out there", "gods": "the gods", "magic": "magic", "money": "money", "ruler": "who rules here",
	"sea": "the sea", "travel": "the roads", "joke": "jokes", "stars": "the stars", "animals": "animals", "health": "health",
	"history": "the old days", "home": "home", "worry": "my worries", "likes": "what I like"}

const INSULT_WORDS := ["stupid", "idiot", "ugly", "shut up", "hate you", "fool", "moron", "dumb", "loser", "you smell", "you stink", "stinks",
	"coward", "pathetic", "worthless", "bastard", "freak", "liar", "scum", "imbecile", "clown", "get lost", "go away",
	"you're boring", "so boring", "dimwit", "halfwit", "creep", "you suck", "ugly"]
const COMPLIMENT_WORDS := ["kind", "beautiful", "handsome", "pretty", "clever", "smart", "wise", "lovely", "nice", "brave", "great",
	"amazing", "wonderful", "cool", "funny", "strong", "good at", "the best", "charming", "gorgeous", "interesting", "like you", "love you"]
const GREET_WORDS := ["hello", "hi", "hey", "greetings", "good morning", "good evening", "good afternoon", "good day", "howdy", "morning", "evening", "hiya", "yo", "well met"]
const YESNO_WORDS := ["yes", "yeah", "yep", "aye", "sure", "ok", "okay", "no", "nope", "nay", "maybe", "perhaps", "i guess", "i suppose", "fine", "alright"]

## Retorts to an insult, by temper.
const RETORT := {
	"gruff": ["Say that again and you'll be picking your teeth up off the ground.", "Watch your mouth{a}.", "I've flattened bigger fools than you.",
		"Big words from someone so far from home.", "Keep talking. See where it gets you."],
	"timid": ["That's... that's not very nice.", "Why would you say that?", "I... I don't have to listen to this.", "Oh. Right. Sorry I spoke."],
	"warm": ["Oh, that stung. Bad day, was it?", "Now, now. No call for that.", "I'll pretend I didn't hear that{a}.", "Well! Your mother'd be ashamed."],
	"greedy": ["Insults are free. My patience isn't.", "Keep that up and my prices double.", "Charming. That'll cost you."],
	"curious": ["Huh. Why would you say that?", "Is that how they talk where you're from?", "Interesting. Rude, but interesting."],
	"plain": ["Charming.", "And good day to you too.", "No call for that.", "Mind your tongue{a}."],
	"child": ["You're the stupid one!", "I'm telling my mum!", "Takes one to know one!", "Meanie."],
}
const RETORT_CULTURE := {
	"old": ["Away with you, you churl.", "Mouth like a midden, you have.", "You've the manners of a pig in a pantry."],
	"fey": ["Your words are thorns. They will grow back into you.", "The wood hears how you speak, far-walker."],
	"frontier": ["Real classy.", "Wow. Okay. Noted.", "Say that outside the perimeter and see who comes to help you."],
	"vex": ["Your hostility is recorded.", "How very human.", "I have catalogued your rudeness. It is extensive."],
}
## Thanks for a compliment, by temper.
const FLATTERED := {
	"gruff": ["Hm. Flattery won't get you a discount.", "Don't push it.", "Aye, well. Fine."],
	"timid": ["Oh! Oh, that's... thank you.", "Really? Nobody's said that before.", "Oh, stop. You're making me blush."],
	"warm": ["Oh, you charmer! Thank you{a}.", "Well, that's made my day.", "Aren't you a sweet one."],
	"greedy": ["Flattery's nice. Coin's nicer.", "Ha! Keep talking, I like it."],
	"curious": ["Really? What makes you say that?", "Ha! Well, thank you. Do go on."],
	"plain": ["Kind of you to say.", "Thank you{a}. That's nice to hear.", "Well, thank you."],
	"child": ["Really? Thanks!", "I know!", "Hee hee. Thanks."],
}
const THANKED := ["Kind of you to say.", "Think nothing of it{a}.", "Any time.", "Glad to be of use.", "Don't mention it.", "No trouble at all{a}."]

# --- Self, place, news, work, farewells ------------------------------------------------------

const ABOUT_SELF := {
	"all": ["I'm {first}. {job_line}", "Name's {first}. I'm the {job} here, have been for years.", "{name}, {job} by trade. Not much more to tell.",
		"They call me {first}. I'm the {job}. I'm partial to {likes}, if you're asking.", "{first}. I keep busy as the {job}. And you are?"],
	"fey": ["I am {first}, {job} of this grove.", "My name is {first}. The trees knew it before I did.", "{first}, they call me. I am the {job}, and I love {likes}.",
		"I am {first}. I have been {job} here since the old oak was a sapling. Nearly."],
	"frontier": ["{first}. {job}. That's the short version.", "Name's {first}. I'm the {job} out here. Somebody's got to be."],
	"vex": ["I am {name}. I serve as {job}. You may use the short name, {first}.", "{first}. {job}. My function is not complicated.",
		"I am designated {first}. I am the {job} of this holding.", "{first}. I serve. I also enjoy {likes}, which my clutch-kin find strange."],
	"child": ["I'm {first}! I'm {age}. What's your name?", "{first}. My mum calls me trouble, but that's not my name."],
}
const PLACE := {
	"old": ["This is {town}. Honest folk, hard work, and the ale's not bad.", "{town}. Quiet, mostly. We like it that way.",
		"Welcome to {town}. Market's in the square, {trader} keeps the stall.", "{town}, and proud of it. Don't ask about the smell by the tannery.",
		"You're in {town}. Small place. Everyone knows everyone's business."],
	"fey": ["You stand in {town}. The glow-moss keeps the old paths lit.", "{town}, where the old trees listen.", "This is {town}. Walk gently, it is older than you think."],
	"frontier": ["{town}. Not much, but the air scrubbers work and the walls hold.", "Welcome to {town}. Last stop before the long nothing.",
		"{town}. Population: not enough. Supplies: never enough.", "You're in {town}. Keep your gear close and your water closer."],
	"vex": ["This is {town}, a spire-holding of the Vex.", "{town}. Every surface here was grown to purpose.", "You stand in {town}. Do not lean on the walls. They are listening."],
	"boat": ["Welcome aboard {town}. Mind your footing, the deck moves.", "This is {town}. She's old, but she floats.", "You're on {town}. Keep out of the crew's way and we'll get on."],
}
const NO_NEWS := ["Quiet lately. Too quiet, if you ask me.", "Nothing much. Same as yesterday.", "Not a thing. Which suits me fine.", "News? Round here? You're joking."]

## What they say about their trade.
const JOB_TALK := {
	"farmer": ["Up before the sun, in bed after it. Farming's simple like that.", "Barley's coming on nicely. Don't jinx it.", "The soil's good here, if you treat it right."],
	"smith": ["Iron's honest. Hit it right and it does what you want.", "Horseshoes, mostly. Nails. The odd blade, if someone pays.", "Forge has been hot since dawn."],
	"guard": ["I walk the walls, watch the road and keep folk out of trouble.", "Quiet watch so far. I like quiet watches.", "Someone has to keep order. Today it's me."],
	"innkeeper": ["I pour the ale, I hear the gossip, and I throw out the drunks.", "Rooms are clean, the stew's hot, the beds have only a few fleas."],
	"hunter": ["Deer, boar, rabbit. Whatever the woods give.", "Out at dawn, back by dusk, with meat if I'm lucky."],
	"priest": ["I tend the shrine and the souls of this place. Both need patching.", "Births, weddings, burials. I see them all."],
	"weaver": ["Wool in, cloth out. Sounds simple. It isn't.", "This blue took a week to dye. Look at it."],
	"miller": ["Grain in, flour out. Mind the stones, they bite.", "The mill wheel's older than me. Creaks like me too."],
	"herbalist": ["Roots and leaves, for whatever ails you.", "Willowbark for pain, mint for the belly. Simple remedies."],
	"warden": ["I watch the edges of the wood, where trouble comes from.", "The paths need watching. The paths always need watching."],
	"runecarver": ["Each rune holds a meaning. Carve it wrong and it holds a curse.", "Slow work. Patient work."],
	"bard": ["I sing for my supper. Some nights I go hungry.", "A song for every season. A verse for every coin."],
	"mystic": ["I listen to what others don't hear.", "Brews, rites, and a great deal of waiting."],
	"beekeeper": ["The bees do the work. I just take the credit, and the honey.", "Calm hands and slow breath, that's the trick with bees."],
	"lamplighter": ["Dusk and dawn, I walk the lamps. Nobody notices until I'm late.", "Light the lamps, douse the lamps. Simple life."],
	"scribe": ["Letters, deeds, accounts. I write what others can't.", "Ink on my fingers since I was eight."],
	"engineer": ["If it's broken, I fix it. If it isn't, give it a week.", "Generators, pumps, comms. All held together with tape and hope."],
	"medic": ["Patch them up, send them out. Repeat.", "Mostly burns and broken fingers. Sometimes worse."],
	"scavenger": ["Out in the ruins, picking through what the old world left.", "One person's junk is my dinner."],
	"pilot": ["I fly supply runs. When there's fuel.", "Up there it's quiet. Down here, never."],
	"security officer": ["Gate duty, patrols, the odd drunk. Keeps me busy.", "I keep the perimeter tight. Nobody gets in that shouldn't."],
	"data broker": ["I buy what people know and sell it to people who don't.", "Information. It's the only thing out here that doesn't rust."],
	"hydroponics tech": ["Lettuce, beans, algae. Glamorous, I know.", "The beds need balancing every hour. Plants are fussier than people."],
	"courier": ["Parcels, letters, bad news. I carry it all.", "If it fits on my back, I'll get it there."],
	"trader": ["I buy cheap and sell fair. Mostly fair.", "Bit of everything on the stall. Have a look."],
	"fisher": ["Nets out at dawn, in by noon.", "Good shoals this week. Won't last."],
	"captain": ["I keep her afloat and the crew in line. Most days.", "Every soul aboard is my responsibility."],
	"sailor": ["Rope, sail and salt. That's my life.", "Crossed these waters more times than I can count."],
	"deckhand": ["Scrub, haul, repeat. Glamorous life at sea.", "Whatever the skipper says, I do."],
	"lookout": ["I watch for rocks, weather and sails. Mostly rocks.", "Best view on the ship, worst seat."],
	"ship's cook": ["I keep the crew fed. Hardest job aboard.", "Salt pork and biscuit, mostly. Don't complain."],
	"castaway": ["Work? I've been trying not to die.", "My ship went down. I'm just trying to reach land."],
	"boat pilot": ["I run the launch. Ferry, tow, fish, whatever pays.", "Engine's temperamental, like me."],
	"marine biologist": ["I study what lives down there. More than you'd think.", "The reef's changing. I'm trying to work out why."],
	"ship engineer": ["Engines, pumps, winches. If it turns, I fix it.", "She's got an old heart, this boat. Still beats."],
}
const WORK_VEX := ["My function is {job}. It is sufficient.", "I am the {job}. The work is precise. I like precise.", "{job}. The hive assigned it. I do not complain."]
const WORK_GENERIC := ["I'm the {job} here. It keeps me busy.", "{job}. It's a living.", "Being the {job} isn't glamorous, but someone has to.",
	"I'm the {job}. Long hours, fair pay, mostly."]

const FAREWELL := {
	"old": ["Safe roads{a}.", "Off with you, then.", "Gods keep you{a}.", "Mind how you go.", "Take care on the road{a}.", "Go well{a}.", "Don't be a stranger."],
	"fey": ["May the light find you.", "Go gently{a}.", "The wood remembers.", "Walk softly{a}.", "Until the leaves turn again."],
	"frontier": ["Stay frosty.", "Clear skies{a}.", "Watch yourself out there.", "Catch you later{a}.", "Don't get yourself killed."],
	"vex": ["Go, and return intact.", "Farewell{a}. Do not die needlessly.", "Your departure is noted.", "Until the next cycle{a}."],
	"child": ["Bye! Come back soon!", "Bye bye!", "See you later!"],
	"night": ["Sleep well{a}.", "Mind the dark{a}.", "Get some rest."],
	"morning": ["Enjoy the day{a}.", "Have a good one."],
}

# --- Barks -----------------------------------------------------------------------------------

const BARK := {
	"confront": ["That's far enough. Put it away.", "One more step and you'll regret it.", "We know what you did.", "Stop right there.",
		"Not another step{a}.", "I'm warning you. Back off."],
	"attack_old": ["You'll pay for that!", "To arms!", "Have at you!", "Get them!", "You asked for this!"],
	"attack_fey": ["The wood defends its own!", "Thorns take you!", "You will not leave this grove!"],
	"attack_frontier": ["Hostile engaged!", "Contact! Contact!", "Light them up!", "You picked the wrong outpost!"],
	"attack_vex": ["Threat confirmed. Correcting.", "You will be removed.", "Error. Eliminate."],
	"flee": ["Help! Help!", "Stay away from me!", "Somebody stop them!", "Guards! Guards!", "Run!", "Leave me alone!"],
	"flee_child": ["Mum! Mum!", "Help!", "Waaah!"],
	"hurt": ["Argh!", "What are you doing?", "Stop!", "Ow! That hurt!", "Are you mad?", "Hey!"],
	"hostile": ["Keep away from me.", "I've nothing to say to you.", "Leave, before I call the guard.", "Go away.", "Don't you come near me.", "You've some nerve, showing your face."],
}

# --- People ----------------------------------------------------------------------------------

## How this person speaks: "old" (medieval human), "fey" (Sylvari), "frontier" (human
## sci-fi) or "vex" (the alien Vex). Human worlds never get "fey".
static func culture(npc: Dictionary) -> String:
	var race := String(npc.get("race", "Human"))
	var era := int(npc.get("era", 0))
	var c := "old"
	if race == "Vex":
		c = "vex"
	elif race == "Sylvari" or era == Eras.FANTASY:
		c = "fey"
	elif era == Eras.SCIFI:
		c = "frontier"
	if Eras.theme == "human" and c in ["fey", "vex"]:
		c = "frontier" if era == Eras.SCIFI else "old"
	return c

static func is_child(npc: Dictionary) -> bool:
	return bool(npc.get("child", false)) or int(npc.get("age", 30)) < 14

## Stable verbal habits, from the person's id and nature.
static func persona(npc: Dictionary) -> Dictionary:
	var h := absi(hash(String(npc.get("id", "")) + "voice"))
	var t: Dictionary = npc.get("traits", {})
	var fr := float(t.get("friendly", 0.5))
	var br := float(t.get("brave", 0.5))
	var gr := float(t.get("greedy", 0.5))
	var cu := float(t.get("curious", 0.5))
	var c := culture(npc)
	var child := is_child(npc)
	var tone := "plain"
	if child:
		tone = "child"
	elif fr < 0.3 and br >= 0.35:
		tone = "gruff"
	elif br < 0.28:
		tone = "timid"
	elif gr > 0.72:
		tone = "greedy"
	elif fr > 0.68:
		tone = "warm"
	elif cu > 0.7:
		tone = "curious"
	var key := "child" if child else c
	var elder := not child and int(npc.get("age", 30)) >= 58
	var pets: Array = PET[key]
	var pet: String = pets[h % pets.size()]
	if elder and (h >> 3) % 2 == 0:
		pet = PET["elder"][(h >> 5) % PET["elder"].size()]
	var addr: Dictionary = ADDR[c]
	var far: Array = addr["far"]
	var near: Array = addr["near"]
	var near_word: String = near[(h >> 7) % near.size()]
	# Warm older folk call everyone love (or their culture's word for it).
	if tone == "warm" and (elder or (h >> 9) % 3 == 0):
		near_word = addr["warm"][(h >> 11) % addr["warm"].size()]
	return {
		"culture": c, "key": key, "tone": tone, "child": child, "elder": elder,
		"pet": pet, "pet_rate": 0.12 + float((h >> 13) % 25) / 100.0,
		"filler": FILLER[key][(h >> 15) % FILLER[key].size()], "filler_rate": float((h >> 17) % 30) / 100.0,
		"lead": LEAD[key][(h >> 19) % LEAD[key].size()], "lead_rate": float((h >> 21) % 30) / 100.0,
		"far": "" if child else far[(h >> 23) % far.size()], "near": "" if child else near_word,
		"addr_rate": 0.25 + float((h >> 25) % 45) / 100.0,
	}

## A random source for one line: who, about what, and when (the hour, the day and what
## they said last), so the same question gets a different answer later on.
static func rng_for(npc: Dictionary, salt: String) -> RandomNumberGenerator:
	var said: Array = npc.get("_said", [])
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s|%s|%d|%d|%d" % [npc.get("id", ""), salt, int(NPCMind.game_day() * 48.0), said.size(), said[-1] if not said.is_empty() else 0])
	return r

## Picks a line from `pool` that this person hasn't said lately.
static func pick(npc: Dictionary, pool: Array, r: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return ""
	var said: Array = npc.get("_said", [])
	var start := r.randi() % pool.size()
	for i in pool.size():
		var line: String = pool[(start + i) % pool.size()]
		if not said.has(hash(line)):
			return line
	return pool[start]

## Notes that this person said `line` (they avoid it for a while).
static func note_said(npc: Dictionary, line: String) -> void:
	if not npc.has("_said") or not (npc["_said"] is Array):
		npc["_said"] = []
	var said: Array = npc["_said"]
	said.append(hash(line))
	while said.size() > SAID_MAX:
		said.pop_front()

## Fills the {placeholders}. The first {a} becomes how they address the traveller (or
## nothing); any later ones are dropped.
static func fill(npc: Dictionary, settlement: Dictionary, s: String, r: RandomNumberGenerator, extra := {}) -> String:
	var p := persona(npc)
	var c: String = p["culture"]
	var v: Dictionary = VOCAB[c]
	var rel := int(npc.get("rel", 0))
	var word: String = p["near"] if rel >= 25 else (p["far"] if rel > -5 else "")
	var a := (", " + word) if word != "" and r.randf() < float(p["addr_rate"]) else ""
	var at := s.find("{a}")
	if at >= 0:
		s = s.substr(0, at) + a + s.substr(at + 3).replace("{a}", "")
	var name := String(npc.get("name", "someone"))
	var d := {
		"first": name.split(" ")[0], "name": name, "job": String(npc.get("job", "worker")),
		"likes": String(npc.get("likes", "a quiet life")), "worry": String(npc.get("worry", "the way things are going")),
		"town": String(settlement.get("name", "this place")), "ruler": v["ruler"], "drink": v["drink"], "gods": v["gods"],
		"beast": v["beast"], "inn": v["inn"], "coin": "Marks", "day": str(NPCMind.day_num()), "age": str(npc.get("age", 30)),
		"age1": str(int(npc.get("age", 30)) + 1), "time": NPCMind.time_words(NPCMind.hour_now()), "doing": doing(npc),
		"trader": _trader(settlement), "job_line": _job_line(npc, r),
	}
	if s.contains("{n1"):
		var nb := neighbour(npc, settlement, r)
		d["n1"] = String(nb.get("name", "the miller")).split(" ")[0]
		d["n1job"] = String(nb.get("job", "miller"))
	d.merge(extra, true)
	s = s.format(d)
	# A sentence that starts with a filled-in word gets its capital.
	return capitalize(s)

## Upper-cases the first letter of every sentence.
static func capitalize(s: String) -> String:
	var start := true
	var out := ""
	for ch in s:
		if start and ch != " " and ch != "\"":
			out += ch.to_upper()
			start = false
		else:
			out += ch
		if ch in [".", "!", "?"]:
			start = true
	return out

## What they are doing right now, in their own words ("" if nothing).
static func doing(npc: Dictionary) -> String:
	return String(npc.get("_duty", "")).replace("your ", "my ").replace("you ", "I ")

static func _trader(settlement: Dictionary) -> String:
	for p in settlement.get("npcs", []):
		if p.get("job", "") == "trader":
			return String(p["name"]).split(" ")[0]
	return "the trader"

## Another living person of their settlement, for gossip ({} if none).
static func neighbour(npc: Dictionary, settlement: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var others: Array = settlement.get("npcs", []).filter(func(o): return o.get("id", "") != npc.get("id", "") and not o.get("dead", false))
	return others[r.randi() % others.size()] if not others.is_empty() else {}

static func _job_line(npc: Dictionary, r: RandomNumberGenerator) -> String:
	var l: Array = JOB_TALK.get(String(npc.get("job", "")), [])
	return l[r.randi() % l.size()] if not l.is_empty() else "I work as the %s here." % npc.get("job", "worker")

## Lines a topic offers this person: those for any culture plus their own.
static func pool(bank: Dictionary, p: Dictionary) -> Array:
	var out: Array = []
	if p["child"] and bank.has("child"):
		return (bank["child"] as Array).duplicate()
	var own: Array = bank.get(p["culture"], [])
	# The Sylvari and the Vex mostly keep to their own way of saying things.
	if p["culture"] in ["fey", "vex"] and own.size() >= 2:
		return own.duplicate()
	out.append_array(bank.get("all", []))
	out.append_array(own)
	return out

## Dresses a line in the person's habits: sometimes an opener for their temper or mood,
## a lead word, a filler at the end of the first sentence, or their pet phrase after it.
static func compose(npc: Dictionary, body: String, r: RandomNumberGenerator, opener := true) -> String:
	var p := persona(npc)
	var mood := String(npc.get("mood", "calm"))
	var out := body
	if opener and r.randf() < 0.3:
		var ops: Array = MOOD_OPENER.get(mood, OPENER.get(p["tone"], OPENER["plain"]))
		out = String(ops[r.randi() % ops.size()]) + " " + out
	elif r.randf() < float(p["lead_rate"]) and not out.begins_with("\"") and _can_lower(out):
		out = String(p["lead"]) + " " + out[0].to_lower() + out.substr(1)
	if r.randf() < float(p["filler_rate"]):
		var dot := out.find(". ")
		if dot < 0 and out.ends_with("."):
			dot = out.length() - 1
		if dot > 20 and not out.substr(0, dot).contains(",") and not out.substr(0, dot).contains("?") and not out.substr(0, dot).contains("!"):
			out = out.substr(0, dot) + ", " + String(p["filler"]) + out.substr(dot)
	# The pet phrase, but not again while they still remember saying it.
	if r.randf() < float(p["pet_rate"]) and out.length() < 110 and not out.ends_with("?") and not (npc.get("_said", []) as Array).has(hash(p["pet"])):
		out += " " + String(p["pet"])
		note_said(npc, p["pet"])
	return out

## Whether a line's first word can be lower-cased after a lead word ("I", names and
## placeholders keep their capitals).
static func _can_lower(s: String) -> bool:
	if s.length() < 2 or s.begins_with("{") or s.begins_with("I ") or s.begins_with("I'"):
		return false
	var w := s.split(" ")[0]
	# "Oh!", "Ha." or "Right," are already a lead of their own.
	if w.ends_with(".") or w.ends_with(",") or w.ends_with("!") or w.ends_with("?") or w in ["Oh", "Ha", "Hah", "Ah", "Hm", "Hey", "Well", "So", "Look"]:
		return false
	return not w in ["Gods", "Mum", "Dad"] and s[0] == s[0].to_upper()

## Finishes a line: fills it in, dresses it in the person's habits, and remembers saying it.
static func say(npc: Dictionary, settlement: Dictionary, template: String, r: RandomNumberGenerator, opener := true, extra := {}) -> String:
	note_said(npc, template)
	return fill(npc, settlement, compose(npc, template, r, opener), r, extra)

# --- What they say ---------------------------------------------------------------------------

## The time-of-day slot for greetings.
static func slot(h: float) -> String:
	if h < 5.0: return "night"
	if h < 7.5: return "dawn"
	if h < 12.0: return "morning"
	if h < 14.0: return "midday"
	if h < 18.0: return "afternoon"
	if h < 21.5: return "evening"
	return "night"

## Whether they know the traveller (talked before, not just this once).
static func knows(npc: Dictionary) -> bool:
	var met := int(npc.get("met", 0))
	return met >= 2 or int(npc.get("rel", 0)) >= 15 or (met >= 1 and (npc.get("mem", []) as Array).size() >= 2)

## The last thing they talked about with the traveller ("" if none).
static func last_topic(npc: Dictionary) -> String:
	var mem: Array = npc.get("mem", [])
	for i in range(mem.size() - 1, maxi(-1, mem.size() - 4), -1):
		var m := RegEx.create_from_string("Talked with the traveller about (.+)\\.$").search(String(mem[i]))
		if m:
			return m.get_string(1).replace("my worries", "your worries").replace("what I like", "what I like")
	return ""

## A greeting: to a passer-by, or as the traveller walks up.
static func greet(npc: Dictionary, settlement := {}) -> String:
	var p := persona(npc)
	var r := rng_for(npc, "greet")
	var c: String = p["culture"]
	var key: String = p["key"]
	var rel := int(npc.get("rel", 0))
	var pool: Array = []
	if knows(npc):
		var band := "fond" if rel >= 25 else ("cold" if rel < -5 else "known")
		pool.append_array(BACK_GREET[key][band])
		var topic := last_topic(npc)
		if topic != "" and band != "cold" and r.randf() < 0.4:
			var line: String = RECALL[r.randi() % RECALL.size()]
			return say(npc, settlement, line, r, false, {"topic": topic})
	else:
		pool.append_array(FIRST_GREET[key])
		if not p["child"]:
			pool.append_array(TONE_GREET.get(p["tone"], []))
			pool.append_array(JOB_GREET.get(String(npc.get("job", "")), []))
	if not p["child"] and rel > -5:
		pool.append_array(TIME_GREET[c][slot(NPCMind.hour_now())])
		if doing(npc) != "" and r.randf() < 0.35:
			return say(npc, settlement, BUSY_GREET[r.randi() % BUSY_GREET.size()], r, false)
	return say(npc, settlement, pick(npc, pool, r), r, r.randf() < 0.5)

## A goodbye.
static func farewell(npc: Dictionary, settlement := {}) -> String:
	var p := persona(npc)
	var r := rng_for(npc, "bye")
	var pool: Array = (FAREWELL[p["key"]] as Array).duplicate()
	var h := NPCMind.hour_now()
	if not p["child"]:
		if h >= 20.0 or h < 4.0:
			pool.append_array(FAREWELL["night"])
		elif h < 11.0:
			pool.append_array(FAREWELL["morning"])
	return say(npc, settlement, pick(npc, pool, r), r, false)

## The topic a line of talk is about ("" if none it knows).
static func topic_of(q: String) -> String:
	for e in TOPIC_WORDS:
		if has_any(q, e[1]):
			return e[0]
	return ""

static var _rx := {}

## Whether `q` contains any of `words` as whole words.
static func has_any(q: String, words: Array) -> bool:
	var key := ",".join(words)
	if not _rx.has(key):
		var esc: Array = words.map(func(w): return String(w).replace("'", "'?"))
		_rx[key] = RegEx.create_from_string("\\b(" + "|".join(esc) + ")\\b")
	return (_rx[key] as RegEx).search(q.to_lower()) != null

## Who spoke rudely or kindly: "insult", "compliment" or "".
static func tone_of(q: String) -> String:
	if has_any(q, INSULT_WORDS):
		return "insult"
	if has_any(q, ["like you", "love you"]):
		return "compliment"
	if not _rx.has("praise"):
		_rx["praise"] = RegEx.create_from_string("\\b(you'?re|you are|you look|you seem|you have|you'?ve got|your)\\b.{0,24}\\b(" + "|".join(COMPLIMENT_WORDS) + ")\\b")
	return "compliment" if (_rx["praise"] as RegEx).search(q.to_lower()) != null else ""

## A line about a topic, often turned to the person's own concerns or a question back.
## Returns {say, remember, mood?, do?}.
static func topic_reply(npc: Dictionary, settlement: Dictionary, topic: String, q: String) -> Dictionary:
	var p := persona(npc)
	var r := rng_for(npc, "topic" + topic + q)
	var out := {"remember": ""}
	var body := ""
	match topic:
		"howareyou":
			var mood := String(npc.get("mood", "calm"))
			if float(npc.get("energy", 1.0)) < 0.3 and mood == "calm":
				mood = "tired"
			body = pick(npc, TOPICS["howareyou"].get(mood, TOPICS["howareyou"]["calm"]), r)
		"player":
			var rel := int(npc.get("rel", 0))
			body = pick(npc, TOPICS["player"]["fond" if rel >= 25 else ("cold" if rel < -5 else "stranger")], r)
			if int(npc.get("met", 0)) >= 3 and r.randf() < 0.5:
				body += " We've talked, what, %d times now?" % int(npc["met"])
		"work":
			body = work_line(npc, r)
		_:
			var bank: Dictionary = TOPICS.get(topic, {})
			var lines := pool(bank, p)
			if lines.is_empty():
				lines = pool(TOPICS["yesno"], p)
			body = pick(npc, lines, r)
			if TOPIC_NAMES.has(topic) and not (npc.get("mem", []) as Array).any(func(m): return String(m).ends_with("about %s." % TOPIC_NAMES[topic])):
				out["remember"] = "Talked with the traveller about %s." % TOPIC_NAMES[topic]
	var line := say(npc, settlement, body, r)
	if topic not in ["howareyou", "time", "yesno", "age"] and r.randf() < 0.55:
		line += " " + turn(npc, settlement, r)
	elif topic in ["howareyou", "yesno"] and r.randf() < 0.6:
		line += " " + fill(npc, settlement, pick(npc, TURN_ASK[p["key"]], r), r)
	out["say"] = line
	return out

## Moves the talk on to what this person cares about: a worry, a liking, a rumour or a
## neighbour, or a question for the traveller.
static func turn(npc: Dictionary, settlement: Dictionary, r: RandomNumberGenerator) -> String:
	var p := persona(npc)
	var t: Dictionary = npc.get("traits", {})
	var rum: Array = settlement.get("rumors", [])
	var roll := r.randf()
	var curious := float(t.get("curious", 0.5))
	var line := ""
	if roll < 0.15 + curious * 0.3:
		line = pick(npc, TURN_ASK[p["key"]], r)
	elif roll < 0.55 and not p["child"]:
		line = pick(npc, TURN_WORRY if r.randf() < 0.55 else TURN_LIKES, r)
	elif roll < 0.75 and not rum.is_empty():
		var news := String(rum[r.randi() % rum.size()]).split(": ", true, 1)[-1]
		return fill(npc, settlement, pick(npc, TURN_RUMOR, r), r, {"rumor": news})
	elif not p["child"] and (settlement.get("npcs", []) as Array).size() > 1 and String(p["culture"]) != "vex":
		line = pick(npc, TURN_GOSSIP, r)
	else:
		line = pick(npc, TURN_ASK[p["key"]], r)
	note_said(npc, line)
	return fill(npc, settlement, line, r)

## When they don't follow what was said: an honest shrug, then they carry the talk on.
static func puzzled(npc: Dictionary, settlement: Dictionary, q: String) -> String:
	var p := persona(npc)
	var r := rng_for(npc, "huh" + q)
	var first := ""
	var w := salient_word(q)
	if w != "" and not p["child"] and String(p["culture"]) == "old" and r.randf() < 0.3:
		first = fill(npc, settlement, ECHO[r.randi() % ECHO.size()], r, {"w": w})
	else:
		first = say(npc, settlement, pick(npc, PUZZLED[p["key"]], r), r)
	return first + " " + turn(npc, settlement, r)

const STOP := ["about", "would", "could", "should", "there", "their", "where", "which", "these", "those", "think", "really",
	"things", "something", "anything", "nothing", "because", "always", "never", "maybe", "today", "going", "doing", "being",
	"other", "every", "after", "before", "still", "while", "without", "again", "people", "thing", "where's", "what's", "you're",
	"don't", "doesn't", "didn't", "isn't", "can't", "won't", "yours", "whats", "trust", "right", "please", "thank", "thanks"]

## The longest plain word the traveller used ("" if none worth echoing).
static func salient_word(q: String) -> String:
	var best := ""
	for raw in q.to_lower().split(" ", false):
		var w := String(raw).strip_edges().trim_suffix("?").trim_suffix("!").trim_suffix(".").trim_suffix(",")
		if w.length() >= 5 and w.length() <= 12 and w.is_valid_identifier() and not STOP.has(w) and w.length() > best.length():
			best = w
	return best

## An answer to rudeness. Returns {say, rel_change, mood, do}.
static func insulted(npc: Dictionary, settlement: Dictionary, q: String) -> Dictionary:
	var p := persona(npc)
	var r := rng_for(npc, "rude" + q)
	var tone: String = p["tone"]
	var pool: Array = (RETORT[tone] as Array).duplicate()
	if not p["child"]:
		pool.append_array(RETORT_CULTURE[p["culture"]])
	var brave := float(npc.get("traits", {}).get("brave", 0.5))
	var mood := "angry" if brave >= 0.4 or tone == "gruff" else "sad"
	var gesture := "fist" if tone == "gruff" and brave > 0.6 else ("hips" if mood == "angry" else "shake_head")
	return {"say": say(npc, settlement, pick(npc, pool, r), r, false), "rel_change": -6 if tone in ["gruff", "timid"] else -4,
		"mood": mood, "do": gesture, "remember": "The traveller insulted me."}

## An answer to a kind word. Returns {say, rel_change, mood, do}.
static func flattered(npc: Dictionary, settlement: Dictionary, q: String) -> Dictionary:
	var p := persona(npc)
	var r := rng_for(npc, "nice" + q)
	var line := say(npc, settlement, pick(npc, FLATTERED[p["tone"]], r), r, false)
	if r.randf() < 0.4:
		line += " " + turn(npc, settlement, r)
	return {"say": line, "rel_change": 1 if p["tone"] == "gruff" else 3, "mood": "happy" if p["tone"] != "gruff" else String(npc.get("mood", "calm")),
		"do": ["nod", "bow", "tilt"][r.randi() % 3] if p["tone"] != "child" else "cheer"}

static func thanked(npc: Dictionary, settlement: Dictionary) -> String:
	var r := rng_for(npc, "thanks")
	return say(npc, settlement, pick(npc, THANKED, r), r, false)

## Who they are.
static func about_self(npc: Dictionary, settlement: Dictionary) -> String:
	var p := persona(npc)
	var r := rng_for(npc, "self")
	var bank: Array = pool(ABOUT_SELF, p)
	var line := say(npc, settlement, pick(npc, bank, r), r, false)
	if doing(npc) != "" and r.randf() < 0.4:
		line += " " + fill(npc, settlement, "Right now I'm {doing}.", r)
	return line

## About the place they live.
static func about_place(npc: Dictionary, settlement: Dictionary) -> String:
	var p := persona(npc)
	var r := rng_for(npc, "place")
	var bank: Array = PLACE["boat"] if settlement.has("boat") else PLACE[p["culture"]]
	var line := say(npc, settlement, pick(npc, bank, r), r, false)
	if r.randf() < 0.5:
		line += " " + turn(npc, settlement, r)
	return line

## The news: a rumour from town, gossip about a neighbour, or their own worry.
static func news(npc: Dictionary, settlement: Dictionary) -> String:
	var r := rng_for(npc, "news")
	var rum: Array = settlement.get("rumors", [])
	if not rum.is_empty() and r.randf() < 0.8:
		var latest := String(rum[-1] if r.randf() < 0.6 else rum[r.randi() % rum.size()]).split(": ", true, 1)[-1]
		return fill(npc, settlement, pick(npc, ["Folk are saying this. {rumor}", "Here's the talk of the town. {rumor}", "Word is, and I only repeat it: {rumor}",
			"You've not heard? {rumor}", "Biggest news this week? {rumor}"], r), r, {"rumor": latest})
	var line := say(npc, settlement, pick(npc, NO_NEWS, r), r, false)
	return line + " " + turn(npc, settlement, r)

## Their work.
static func work_line(npc: Dictionary, r: RandomNumberGenerator) -> String:
	var lines: Array = (JOB_TALK.get(String(npc.get("job", "")), []) as Array).duplicate()
	lines.append_array(WORK_VEX if persona(npc)["culture"] == "vex" else WORK_GENERIC)
	var line := pick(npc, lines, r)
	if doing(npc) != "":
		line += " Right now I'm {doing}."
	return line

## A short line said on their own: "greet", "confront", "attack", "flee", "hurt", "hostile".
static func bark(npc: Dictionary, kind: String, settlement := {}) -> String:
	if kind == "greet":
		return greet(npc, settlement)
	var p := persona(npc)
	var r := rng_for(npc, kind)
	var pool: Array = []
	match kind:
		"attack":
			pool = BARK["attack_" + String(p["culture"])]
		"flee":
			pool = BARK["flee_child"] if p["child"] else BARK["flee"]
		_:
			pool = BARK.get(kind, [])
	if pool.is_empty():
		return ""
	var line := pick(npc, pool, r)
	note_said(npc, line)
	return fill(npc, settlement, line, r)

# --- For the language model ------------------------------------------------------------------

## How each culture talks, for the model.
const DICTION := {
	"old": "the plain speech of medieval village folk: aye, nay, reckon, folk, mind you; no modern words, slang or technology",
	"fey": "the lyrical speech of the Sylvari: images of roots, leaves, moon and water, unhurried, now and then a riddle",
	"frontier": "the wry, practical slang of a human frontier outpost: shifts, rations, comms, scrap, the Company; no thee or thou, nothing fantastical",
	"vex": "the precise, faintly formal speech of the Vex, an alien people: few contractions, oddly literal turns of phrase; humans are outworlders to you",
}
const TONE_WORDS := {"gruff": "gruff and short with people", "warm": "warm and chatty", "timid": "shy and hesitant",
	"greedy": "always angling for coin", "curious": "nosy and full of questions", "plain": "matter-of-fact", "child": "a child"}

## The person's diction and verbal habits for the language model, plus the world's rules
## (nothing glows and nobody believes in magic on a human world).
static func prompt_voice(npc: Dictionary) -> String:
	var p := persona(npc)
	var s := "How you talk: %s. You are %s." % [DICTION[p["culture"]], TONE_WORDS[p["tone"]]]
	if p["child"]:
		s += " You are a child of %d: talk like one, simply and eagerly, and ask lots of questions." % int(npc.get("age", 9))
	else:
		s += " Your habits: you are fond of saying \"%s\" and now and then say \"%s\"; you call strangers \"%s\" and friends \"%s\", but only sometimes." % [String(p["pet"]).trim_suffix("."), p["filler"], p["far"], p["near"]]
	if Eras.theme == "human":
		s += " Nothing glows on this world and there is no magic, no spirits and no fey folk: you know of none and never speak of them as real."
	return s
