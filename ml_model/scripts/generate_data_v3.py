"""
Optimized Training Data Generation for Intent Classification
Version 3 - Faster generation with balanced classes
"""

import csv
import random

# ============================================
# DATA POOLS
# ============================================

ITEMS = [
    "keys", "wallet", "phone", "laptop", "glasses", "watch", "charger", "headphones",
    "earphones", "umbrella", "jacket", "passport", "documents", "book", "notebook",
    "medicine", "water bottle", "backpack", "purse", "bag", "credit card", "debit card",
    "ID card", "car keys", "house keys", "bike keys", "remote", "TV remote", "mouse",
    "keyboard", "cable", "power bank", "camera", "tablet", "iPad", "sunglasses"
]

LOCATIONS = [
    "drawer", "table", "desk", "shelf", "cabinet", "cupboard", "wardrobe", "closet",
    "bedroom", "kitchen", "bathroom", "living room", "office", "car", "bag", "backpack",
    "pocket", "nightstand", "dining table", "counter", "rack", "hook", "box", "safe",
    "locker", "garage", "lot A", "lot B", "top shelf", "bottom drawer", "front pocket"
]

ACCOUNTS = [
    "Netflix", "Amazon", "Gmail", "email", "Facebook", "Instagram", "WiFi", "bank",
    "ATM", "phone", "laptop", "safe", "locker", "door", "garage", "Spotify", "Google",
    "YouTube", "Paytm", "PhonePe", "GPay", "office WiFi", "home WiFi"
]

PASSWORDS = ["abc123", "password123", "qwerty", "letmein", "admin123", "secret456", "test1234", "pass@123"]
PINS = ["1234", "4321", "0000", "5555", "9876", "2468", "1357", "7890"]

RELATIONS = ["mom", "dad", "brother", "sister", "friend", "boss", "colleague", "doctor", "neighbor"]
INFO_TYPES = ["phone number", "number", "birthday", "anniversary", "address"]

EVENTS = ["meeting", "appointment", "interview", "flight", "train", "deadline", "exam", "class", "call"]
TIMES = ["at 9am", "at 10am", "at 2pm", "at 3pm", "at 5pm", "tomorrow", "next week", "on Monday", "on Friday"]

PERSONS = ["John", "Sarah", "Mike", "Emma", "Lisa", "Tom", "mom", "dad", "friend", "colleague"]
AMOUNTS = ["100", "500", "1000", "2000", "5000"]

TASKS = [
    "drink water", "take medicine", "call mom", "call dad", "exercise", "go to gym",
    "wake up", "sleep", "eat breakfast", "eat lunch", "eat dinner", "take a break",
    "stretch", "stand up", "walk around", "check email", "attend meeting", "pay bills",
    "buy groceries", "water the plants", "feed the pet", "take vitamins", "study",
    "read", "meditate", "practice yoga", "charge phone", "clean room", "do laundry"
]

NUMBERS = ["1", "2", "3", "5", "10", "15", "20", "30", "45", "60"]
UNITS_MIN = ["minute", "minutes", "min", "mins"]
UNITS_HOUR = ["hour", "hours", "hr", "hrs"]
FULL_TIMES = ["5am", "6am", "7am", "8am", "9am", "10am", "12pm", "1pm", "2pm", "3pm", "4pm", "5pm", "6pm", "7pm", "8pm"]

CANCEL_VERBS = ["cancel", "delete", "stop", "remove", "clear", "turn off"]
CANCEL_TOPICS = [
    "water", "medicine", "exercise", "gym", "workout", "meeting", "call", "lunch",
    "dinner", "breakfast", "sleep", "wake up", "break", "stretch", "walk", "email",
    "bills", "rent", "grocery", "vitamins", "yoga", "meditation", "reading", "study",
    "morning", "evening", "daily", "hourly", "hydration", "posture"
]

GREETINGS = ["Hello", "Hi", "Hey", "Good morning", "Good evening", "What's up", "How are you", "Yo", "Hiya"]
UNCLEAR_WORDS = ["Keys", "Wallet", "Phone", "Yes", "No", "Maybe", "Okay", "Sure", "Help", "Thanks"]
INCOMPLETE = ["I want to", "Can you", "Please", "My", "Um", "Well", "I think", "Where is", "Remind me"]
RANDOM_PHRASES = ["The weather is nice", "I'm tired", "Never mind", "Whatever", "Nothing", "I see", "Got it"]


def generate_save_samples(count=1700):
    samples = []

    # Location storage templates
    loc_templates = [
        "I put my {item} in the {loc}",
        "I left my {item} on the {loc}",
        "I kept my {item} in the {loc}",
        "My {item} is in the {loc}",
        "My {item} is on the {loc}",
        "The {item} is in the {loc}",
        "I have put my {item} in the {loc}",
        "I stored my {item} in the {loc}",
        "{item} is in the {loc}",
        "I parked my {item} in {loc}",
    ]

    for _ in range(count // 4):
        t = random.choice(loc_templates)
        samples.append(t.format(item=random.choice(ITEMS), loc=random.choice(LOCATIONS)))

    # Password templates
    pwd_templates = [
        "My {acc} password is {pwd}",
        "The {acc} password is {pwd}",
        "{acc} password is {pwd}",
        "My {acc} PIN is {pin}",
        "{acc} PIN is {pin}",
        "The code for {acc} is {pwd}",
        "Password for {acc} is {pwd}",
        "PIN for {acc} is {pin}",
    ]

    for _ in range(count // 4):
        t = random.choice(pwd_templates)
        samples.append(t.format(acc=random.choice(ACCOUNTS), pwd=random.choice(PASSWORDS), pin=random.choice(PINS)))

    # Info templates
    info_templates = [
        "My {rel}'s {info} is {val}",
        "{rel}'s {info} is {val}",
        "My {info} is {val}",
    ]

    for _ in range(count // 6):
        t = random.choice(info_templates)
        val = random.choice(PINS) + str(random.randint(1000, 9999))
        samples.append(t.format(rel=random.choice(RELATIONS), info=random.choice(INFO_TYPES), val=val))

    # Event templates
    event_templates = [
        "The {event} is {time}",
        "My {event} is {time}",
        "I have {event} {time}",
        "Remember that {event} is {time}",
        "Note that {event} is {time}",
        "Don't forget {event} is {time}",
    ]

    for _ in range(count // 6):
        t = random.choice(event_templates)
        samples.append(t.format(event=random.choice(EVENTS), time=random.choice(TIMES)))

    # Money/borrowed templates
    money_templates = [
        "I owe {person} {amt} rupees",
        "I borrowed {amt} from {person}",
        "{person} owes me {amt}",
        "I lent {amt} to {person}",
        "{person} has my {item}",
        "I gave my {item} to {person}",
        "I borrowed the {item} from {person}",
    ]

    for _ in range(count // 6):
        t = random.choice(money_templates)
        samples.append(t.format(person=random.choice(PERSONS), amt=random.choice(AMOUNTS), item=random.choice(ITEMS)))

    return [(s, "save") for s in samples[:count]]


def generate_search_samples(count=1700):
    samples = set()

    # Where questions
    where_templates = [
        "Where are my {item}?",
        "Where is my {item}?",
        "Where did I put my {item}?",
        "Where did I leave my {item}?",
        "Where did I keep my {item}?",
        "Where is the {item}?",
        "Where have I put my {item}?",
        "Where can I find my {item}?",
        "Do you know where my {item} is?",
        "My {item} is where?",
        "Where's my {item}?",
        "Where's the {item}?",
        "Where are the {item}?",
        "Where did I place my {item}?",
        "Where did I store my {item}?",
    ]

    for t in where_templates:
        for item in ITEMS:
            samples.add(t.format(item=item))

    # What questions
    what_templates = [
        "What is my {acc} password?",
        "What is the {acc} password?",
        "What was the {acc} password?",
        "What is my {acc} PIN?",
        "What's my {acc} password?",
        "What's the {acc} password?",
        "What's {acc} password?",
        "What's the PIN for {acc}?",
        "What is {rel}'s {info}?",
        "What time is the {event}?",
        "What did I save about {item}?",
        "What do you know about {item}?",
        "What do I have saved about {item}?",
    ]

    for t in what_templates:
        for acc in ACCOUNTS:
            for rel in RELATIONS:
                for info in INFO_TYPES:
                    for event in EVENTS:
                        for item in ITEMS[:10]:  # Limit to avoid too many
                            samples.add(t.format(acc=acc, rel=rel, info=info, event=event, item=item))
                            if len(samples) >= count * 3:
                                break

    # Did/Do questions
    did_templates = [
        "Did I pay the rent?",
        "Did I take my medicine?",
        "Did I return the {item}?",
        "Do I have {item}?",
        "Do I have any {event} today?",
        "Do I owe {person} money?",
        "Does {person} owe me money?",
        "Did I save {item}?",
        "Have I paid the bills?",
        "Am I supposed to call {person}?",
        "Did I put {item} somewhere?",
        "Have I saved anything about {item}?",
        "Did I note where my {item} is?",
        "Is there any info on {item}?",
        "Do you have info about {item}?",
    ]

    for t in did_templates:
        for item in ITEMS:
            for event in EVENTS:
                for person in PERSONS:
                    samples.add(t.format(item=item, event=event, person=person))

    # Find/Search commands
    find_templates = [
        "Find my {item}",
        "Find the {item}",
        "Search for my {item}",
        "Look for my {item}",
        "Search {item}",
        "Find where I put my {item}",
        "Get my {item} location",
        "Locate my {item}",
        "Help me find my {item}",
        "I need to find my {item}",
        "Can you find my {item}?",
        "Please find my {item}",
        "Look up {item}",
        "Search for {item}",
    ]

    for t in find_templates:
        for item in ITEMS:
            samples.add(t.format(item=item))

    # Tell me questions
    tell_templates = [
        "Tell me where my {item} is",
        "Tell me my {acc} password",
        "Tell me about {item}",
        "Show me where my {item} is",
        "Show me my {acc} password",
        "Give me my {acc} password",
        "Give me the {acc} PIN",
        "Recall where I put my {item}",
        "Remember where my {item} is?",
    ]

    for t in tell_templates:
        for item in ITEMS:
            for acc in ACCOUNTS:
                samples.add(t.format(item=item, acc=acc))

    samples = list(samples)[:count]
    return [(s, "search") for s in samples]


def generate_reminder_samples(count=1900):
    samples = []

    # Basic remind
    basic_templates = [
        "Remind me to {task}",
        "Remind me to {task} please",
        "Set a reminder to {task}",
        "Create a reminder to {task}",
        "I need a reminder to {task}",
        "Reminder to {task}",
        "{task} reminder",
        "Alert me to {task}",
        "Don't let me forget to {task}",
    ]

    for _ in range(count // 5):
        t = random.choice(basic_templates)
        samples.append(t.format(task=random.choice(TASKS)))

    # Duration based (in X minutes)
    dur_templates = [
        "Remind me to {task} in {num} {unit}",
        "Remind me to {task} after {num} {unit}",
        "In {num} {unit} remind me to {task}",
        "After {num} {unit} remind me to {task}",
        "{num} {unit} reminder to {task}",
        "Reminder in {num} {unit} to {task}",
        "{task} in {num} {unit}",
        "{task} after {num} {unit}",
    ]

    for _ in range(count // 4):
        t = random.choice(dur_templates)
        unit = random.choice(UNITS_MIN + UNITS_HOUR)
        samples.append(t.format(task=random.choice(TASKS), num=random.choice(NUMBERS), unit=unit))

    # Static time (at X pm)
    static_templates = [
        "Remind me to {task} at {time}",
        "Remind me at {time} to {task}",
        "Set alarm for {time} to {task}",
        "At {time} remind me to {task}",
        "Reminder at {time} to {task}",
        "{task} at {time}",
        "Wake me up at {time}",
        "Wake me at {time}",
        "Alarm at {time}",
        "Set alarm for {time}",
    ]

    for _ in range(count // 4):
        t = random.choice(static_templates)
        samples.append(t.format(task=random.choice(TASKS), time=random.choice(FULL_TIMES)))

    # Recurring (every X minutes)
    recur_templates = [
        "Remind me to {task} every {num} {unit}",
        "Remind me every {num} {unit} to {task}",
        "Every {num} {unit} remind me to {task}",
        "{task} every {num} {unit}",
        "Every {num} {unit} {task}",
        "Recurring reminder every {num} {unit} to {task}",
        "Repeat reminder to {task} every {num} {unit}",
        "{task} reminder every {num} {unit}",
    ]

    for _ in range(count // 4):
        t = random.choice(recur_templates)
        unit = random.choice(UNITS_MIN + UNITS_HOUR)
        samples.append(t.format(task=random.choice(TASKS), num=random.choice(NUMBERS), unit=unit))

    return [(s, "reminder") for s in samples[:count]]


def generate_cancel_all_samples(count=1400):
    """MUST contain 'all' or 'every' or 'everything'"""
    samples = set()

    templates = [
        "{verb} all reminders",
        "{verb} all my reminders",
        "{verb} all the reminders",
        "{verb} every reminder",
        "{verb} everything",
        "{verb} all of them",
        "I want to {verb} all reminders",
        "I want to {verb} all my reminders",
        "please {verb} all reminders",
        "please {verb} all my reminders",
        "can you {verb} all reminders",
        "can you {verb} all my reminders",
        "just {verb} all reminders",
        "just {verb} all my reminders",
        "get rid of all reminders",
        "get rid of all my reminders",
        "{verb} all alarms",
        "{verb} all alerts",
        "{verb} all notifications",
        "{verb} all active reminders",
        "{verb} all scheduled reminders",
        "{verb} all recurring reminders",
        "I want all reminders gone",
        "{verb} every single reminder",
        "{verb} all pending reminders",
        "wipe all reminders",
        "erase all reminders",
        "kill all reminders",
        "end all reminders",
    ]

    prefixes = ["", "I need to ", "I want to ", "please ", "can you ", "could you ", "just ", "quickly "]
    suffixes = ["", " now", " please", " right now", " immediately", " for me"]

    # Generate all combinations
    for t in templates:
        for verb in CANCEL_VERBS:
            text = t.format(verb=verb)
            for prefix in prefixes:
                for suffix in suffixes:
                    samples.add(prefix + text + suffix)
                    samples.add((prefix + text + suffix).lower())
                    samples.add((prefix + text + suffix).upper())
                    samples.add((prefix + text + suffix).capitalize())

    samples = list(samples)[:count]
    return [(s, "cancel_all") for s in samples]


def generate_cancel_specific_samples(count=1700):
    """NO 'all' or 'every', has specific topic"""
    samples = set()

    templates = [
        "{verb} my {topic} reminder",
        "{verb} the {topic} reminder",
        "{verb} {topic} reminder",
        "{verb} the reminder to {task}",
        "{verb} my reminder to {task}",
        "I don't want the {topic} reminder anymore",
        "I don't need the {topic} reminder",
        "no more {topic} reminder",
        "no need for {topic} reminder",
        "stop reminding me about {topic}",
        "stop reminding me to {task}",
        "don't remind me about {topic} anymore",
        "I no longer need the {topic} reminder",
        "turn off my {topic} reminder",
        "turn off the {topic} reminder",
        "{verb} that {topic} reminder",
        "please {verb} {topic} reminder",
        "can you {verb} the {topic} reminder",
        "I want to {verb} the {topic} reminder",
        "I'd like to {verb} the {topic} reminder",
        "disable {topic} reminder",
        "deactivate {topic} reminder",
    ]

    simple_tasks = ["drink water", "take medicine", "call mom", "exercise", "wake up", "eat lunch", "stretch", "pay bills"]

    # Generate combinations
    for t in templates:
        for verb in CANCEL_VERBS[:4]:  # Only cancel, delete, stop, remove
            for topic in CANCEL_TOPICS:
                for task in simple_tasks:
                    text = t.format(verb=verb, topic=topic, task=task)
                    samples.add(text)
                    if len(samples) >= count * 2:
                        break
                if len(samples) >= count * 2:
                    break
            if len(samples) >= count * 2:
                break
        if len(samples) >= count * 2:
            break

    samples = list(samples)[:count]
    return [(s, "cancel_specific") for s in samples]


def generate_unclear_samples(count=1600):
    samples = set()

    # Greetings
    for g in GREETINGS:
        samples.add(g)
        samples.add(g.lower())
        samples.add(g.upper())

    # Single words
    for w in UNCLEAR_WORDS:
        samples.add(w)
        samples.add(w.lower())

    # Incomplete
    for i in INCOMPLETE:
        samples.add(i)

    # Random phrases
    for r in RANDOM_PHRASES:
        samples.add(r)

    # Gibberish and vague
    gibberish = ["Asdf", "Hmm", "Uh huh", "Huh", "Blah", "Test", "123", "Zzz", "Oops", "Uhh", "La la la",
                 "Aaa", "Bbb", "Xyz", "Lol", "Idk", "Brb", "Omg", "Wow", "Meh", "Nah", "Yep", "Nope"]
    vague = ["What?", "Why?", "How?", "When?", "Really?", "What now?", "And then?", "So what?", "Huh?",
             "Then?", "So?", "And?", "But?", "Like?", "Right?", "Yeah?"]
    conversational = ["Thanks", "Thank you", "Okay", "Great", "Perfect", "Got it", "I see", "Sure", "Fine", "Cool",
                      "Nice", "Alright", "Ok", "K", "Kk", "Yup", "Yes", "No", "Nah", "Maybe"]
    partial = ["I", "My", "The", "Um", "Uh", "So", "Well", "Can", "Re", "Rem", "Del", "Set",
               "A", "An", "It", "Is", "Be", "To", "Do", "Go", "Get", "Put"]
    misc = ["...", "???", "!!!", "Hmmmm", "Ummm", "Errr", "Ahh", "Ohh", "Ehh", "Mhm", "Aha",
            "Just wondering", "Not sure", "I forgot", "Never mind", "Forget it", "Skip", "Pass",
            "One sec", "Hold on", "Wait", "Hmm okay", "Let me think", "I don't know"]

    for item in gibberish + vague + conversational + partial + misc:
        samples.add(item)
        if len(item) > 0 and item[0].isalpha():
            samples.add(item.lower())
            samples.add(item.upper())
            samples.add(item.capitalize())

    # Create more variations
    all_unclear = list(samples)
    for i, item in enumerate(all_unclear):
        if len(samples) >= count:
            break
        samples.add(item + ".")
        samples.add(item + "?")
        samples.add(item + "!")

    samples = list(samples)[:count]
    return [(s, "unclear") for s in samples]


def split_data(samples, train_ratio=0.70, val_ratio=0.15):
    random.shuffle(samples)

    by_label = {}
    for text, label in samples:
        if label not in by_label:
            by_label[label] = []
        by_label[label].append((text, label))

    train, val, test = [], [], []

    for label, items in by_label.items():
        random.shuffle(items)
        n = len(items)
        t1 = int(n * train_ratio)
        t2 = t1 + int(n * val_ratio)

        train.extend(items[:t1])
        val.extend(items[t1:t2])
        test.extend(items[t2:])

    random.shuffle(train)
    random.shuffle(val)
    random.shuffle(test)

    return train, val, test


def save_csv(data, path):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['text', 'label'])
        for text, label in data:
            writer.writerow([text, label])
    print(f"Saved {len(data)} to {path}")


def main():
    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))
    base_dir = os.path.dirname(script_dir)

    print("Generating training data v3...")

    save = generate_save_samples(1700)
    print(f"save: {len(save)}")

    search = generate_search_samples(1700)
    print(f"search: {len(search)}")

    reminder = generate_reminder_samples(1900)
    print(f"reminder: {len(reminder)}")

    cancel_all = generate_cancel_all_samples(1400)
    print(f"cancel_all: {len(cancel_all)}")

    cancel_specific = generate_cancel_specific_samples(1700)
    print(f"cancel_specific: {len(cancel_specific)}")

    unclear = generate_unclear_samples(1600)
    print(f"unclear: {len(unclear)}")

    all_samples = save + search + reminder + cancel_all + cancel_specific + unclear
    print(f"\nTotal: {len(all_samples)}")

    unique = list(set(all_samples))
    print(f"Unique: {len(unique)}")

    train, val, test = split_data(unique)
    print(f"\nTrain: {len(train)}, Val: {len(val)}, Test: {len(test)}")

    # Create directories if they don't exist
    os.makedirs(os.path.join(base_dir, 'data', 'train'), exist_ok=True)
    os.makedirs(os.path.join(base_dir, 'data', 'validation'), exist_ok=True)
    os.makedirs(os.path.join(base_dir, 'data', 'test'), exist_ok=True)

    save_csv(train, os.path.join(base_dir, 'data', 'train', 'intent_train.csv'))
    save_csv(val, os.path.join(base_dir, 'data', 'validation', 'intent_val.csv'))
    save_csv(test, os.path.join(base_dir, 'data', 'test', 'intent_test.csv'))

    print("\nClass distribution (Train):")
    labels = [l for _, l in train]
    for label in ["save", "search", "reminder", "cancel_all", "cancel_specific", "unclear"]:
        c = labels.count(label)
        print(f"  {label}: {c} ({c/len(labels)*100:.1f}%)")

    print("\nDone!")


if __name__ == '__main__':
    main()
