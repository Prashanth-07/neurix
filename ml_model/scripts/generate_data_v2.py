"""
Enhanced Training Data Generation for Intent Classification
Version 2 - Designed for 95-99% accuracy

Key Principles:
1. Each class has DISTINCT linguistic patterns that don't overlap
2. Balanced class distribution
3. Consistent patterns within each class
4. High diversity through systematic variation
"""

import csv
import random
import os
import itertools

# ============================================
# CLASS-SPECIFIC PATTERNS (NON-OVERLAPPING)
# ============================================

"""
PATTERN ANALYSIS:

SAVE - Statements about storing/noting information
  - "I put/left/kept/placed/stored my X in/on Y"
  - "My X password/PIN is Y"
  - "X's birthday/number is Y"
  - "Remember/Note that X"
  - NO question words, NO "remind", NO "cancel"

SEARCH - Questions about retrieving information
  - "Where is/are my X?"
  - "What is my X password?"
  - "Did I X?" / "Do I have X?"
  - "Find/Search/Look for X"
  - MUST have question intent (?, question words, or find/search verbs)

REMINDER - Commands to create reminders
  - "Remind me to X"
  - "Set reminder/alarm for X"
  - Contains time indicators (in X min, at X pm, every X hours)
  - NO "cancel/stop/delete", NO question words

CANCEL_ALL - Cancel ALL reminders (bulk operation)
  - MUST contain "all" or "every" or "everything"
  - Combined with cancel/delete/stop/remove/clear
  - NO specific topic mentioned

CANCEL_SPECIFIC - Cancel ONE specific reminder
  - Contains cancel/stop/delete/remove + specific topic
  - NO "all" or "every"
  - Mentions specific reminder (water, medicine, etc.)

UNCLEAR - Ambiguous/incomplete/unrelated
  - Greetings, single words, gibberish
  - Incomplete sentences
  - Doesn't match other patterns
"""

# ============================================
# SAVE CLASS TEMPLATES
# ============================================

SAVE_DATA = {
    # Pattern 1: Location storage "I [verb] my [item] in/on [location]"
    "location_verbs": ["put", "left", "kept", "placed", "stored", "parked"],
    "location_verbs_past": ["have put", "have left", "have kept", "have placed", "have stored"],

    "items": [
        "keys", "wallet", "phone", "laptop", "glasses", "watch", "charger", "headphones",
        "earphones", "umbrella", "jacket", "coat", "passport", "documents", "book",
        "notebook", "medicine", "water bottle", "backpack", "purse", "bag",
        "credit card", "debit card", "ID card", "car keys", "house keys", "bike keys",
        "remote", "TV remote", "mouse", "keyboard", "cable", "power bank", "camera",
        "tablet", "iPad", "sunglasses", "ring", "necklace", "earrings", "toolbox",
        "pen", "pencil", "car", "bike", "scooter", "lunch box", "water bottle"
    ],

    "locations": [
        "drawer", "table", "desk", "shelf", "cabinet", "cupboard", "wardrobe",
        "closet", "bedroom", "kitchen", "bathroom", "living room", "office",
        "car", "bag", "backpack", "purse", "pocket", "nightstand", "bedside table",
        "dining table", "coffee table", "counter", "rack", "hook", "box", "safe",
        "locker", "garage", "basement", "attic", "balcony", "garden",
        "lot A", "lot B", "lot C", "second floor", "top shelf", "bottom drawer",
        "left drawer", "right drawer", "middle shelf", "front pocket", "side pocket",
        "main compartment", "filing cabinet", "storage room", "guest room"
    ],

    # Pattern 2: Password/PIN storage
    "accounts": [
        "Netflix", "Amazon", "Gmail", "email", "Facebook", "Instagram", "Twitter",
        "LinkedIn", "WiFi", "router", "bank", "ATM", "phone", "laptop", "computer",
        "tablet", "iPad", "safe", "locker", "door", "garage", "office", "alarm",
        "Spotify", "Apple", "Google", "YouTube", "Hotstar", "Prime Video", "Disney",
        "Uber", "Zomato", "Swiggy", "Paytm", "PhonePe", "GPay", "net banking",
        "trading", "Zerodha", "work email", "personal email", "home WiFi", "office WiFi",
        "guest WiFi", "building gate", "credit card", "debit card"
    ],

    "passwords": [
        "abc123", "password123", "qwerty", "letmein", "welcome1", "admin123",
        "secret456", "mypass789", "hello123", "test1234", "user2024", "pass@123",
        "secure#1", "login456", "access789", "key2024", "code1234", "open123",
        "enter456", "unlock789", "master123", "super456", "ultra789", "mega123"
    ],

    "pins": [
        "1234", "4321", "0000", "1111", "2222", "3333", "4444", "5555", "6666",
        "7777", "8888", "9999", "1357", "2468", "9876", "5678", "4567", "3456",
        "2345", "6789", "7890", "8901", "9012", "0123", "1470", "2580", "3690"
    ],

    # Pattern 3: Personal info storage
    "relations": [
        "mom", "dad", "mother", "father", "brother", "sister", "wife", "husband",
        "son", "daughter", "uncle", "aunt", "grandma", "grandpa", "friend", "boss",
        "colleague", "neighbor", "doctor", "dentist", "teacher", "roommate"
    ],

    "info_types": ["phone number", "number", "birthday", "anniversary", "address", "email"],

    # Pattern 4: Event/schedule storage
    "events": [
        "meeting", "appointment", "interview", "call", "flight", "train", "bus",
        "doctor appointment", "dentist appointment", "haircut", "reservation",
        "booking", "checkout", "check-in", "deadline", "submission", "presentation",
        "conference", "webinar", "class", "lecture", "exam", "test", "project review"
    ],

    "time_expressions": [
        "at 9am", "at 10am", "at 11am", "at 12pm", "at 1pm", "at 2pm", "at 3pm",
        "at 4pm", "at 5pm", "at 6pm", "at 7pm", "at 8pm", "at 9pm",
        "tomorrow", "tomorrow morning", "tomorrow evening", "next week",
        "next Monday", "next Tuesday", "on Friday", "on Saturday", "on Sunday",
        "this weekend", "on Monday", "on Tuesday", "on Wednesday", "on Thursday"
    ],

    "dates": [
        "January 15", "February 20", "March 10", "April 5", "May 25", "June 30",
        "the 1st", "the 5th", "the 10th", "the 15th", "the 20th", "the 25th"
    ],

    # Pattern 5: Borrowed/lent money
    "persons": [
        "John", "Sarah", "Mike", "David", "Emma", "Lisa", "Tom", "Anna", "James",
        "Mary", "Robert", "Jennifer", "Chris", "Amy", "Daniel", "Rachel",
        "mom", "dad", "brother", "sister", "friend", "colleague", "roommate", "neighbor"
    ],

    "amounts": ["50", "100", "200", "500", "1000", "1500", "2000", "5000", "10000", "250"],

    # Pattern 6: Other info
    "blood_types": ["O positive", "O negative", "A positive", "A negative",
                    "B positive", "B negative", "AB positive", "AB negative"],
    "sizes": ["small", "medium", "large", "XL", "XXL", "S", "M", "L", "32", "34", "36", "38", "40"],
    "allergies": ["peanuts", "dairy", "gluten", "eggs", "shellfish", "dust", "pollen"],

    "medicines": ["medicine", "paracetamol", "aspirin", "vitamins", "antibiotics",
                  "tablets", "cough syrup", "eye drops", "pain killer"],
    "meals": ["breakfast", "lunch", "dinner", "snacks", "food"],
    "times_simple": ["8am", "9am", "10am", "12pm", "1pm", "2pm", "6pm", "7pm", "8pm", "9pm"],

    "stores": ["Amazon", "Flipkart", "Myntra", "BigBasket", "Swiggy", "Zomato",
               "mall", "supermarket", "grocery store", "pharmacy", "online"]
}


# ============================================
# SEARCH CLASS TEMPLATES
# ============================================

SEARCH_DATA = {
    "items": SAVE_DATA["items"],
    "accounts": SAVE_DATA["accounts"],
    "relations": SAVE_DATA["relations"],
    "info_types": SAVE_DATA["info_types"],
    "events": ["meeting", "appointment", "flight", "train", "interview", "call", "exam"],
    "topics": ["keys", "wallet", "password", "meeting", "flight", "appointment", "car", "phone"],
    "bills": ["electricity bill", "water bill", "phone bill", "internet bill", "rent", "EMI"],
    "actions": [
        "pay the bill", "take medicine", "call mom", "submit the report",
        "attend the meeting", "book tickets", "return the book", "pay rent",
        "charge my phone", "lock the door", "turn off the stove", "feed the pet"
    ]
}


# ============================================
# REMINDER CLASS TEMPLATES
# ============================================

REMINDER_DATA = {
    "tasks": [
        "drink water", "take medicine", "call mom", "call dad", "exercise",
        "go to gym", "wake up", "sleep", "eat breakfast", "eat lunch",
        "eat dinner", "take a break", "stretch", "stand up", "walk around",
        "check email", "reply to messages", "submit report", "attend meeting",
        "join the call", "pay bills", "buy groceries", "pick up laundry",
        "water the plants", "feed the pet", "take vitamins", "do homework",
        "study", "read", "meditate", "practice yoga", "go for a run",
        "charge phone", "backup data", "clean room", "wash dishes", "do laundry",
        "call doctor", "book appointment", "renew subscription", "pay rent",
        "transfer money", "check bank balance", "review documents", "prepare presentation"
    ],

    "numbers_small": ["1", "2", "3", "5", "10", "15", "20", "30", "45"],
    "numbers_large": ["1", "2", "3", "5", "10", "15", "20", "30", "45", "60", "90"],
    "units_minute": ["minute", "minutes", "min", "mins"],
    "units_hour": ["hour", "hours", "hr", "hrs"],

    "times_12h": ["5", "6", "7", "8", "9", "10", "11", "12", "1", "2", "3", "4"],
    "periods": ["am", "AM", "pm", "PM"],
    "full_times": [
        "5am", "6am", "7am", "8am", "9am", "10am", "11am", "12pm",
        "1pm", "2pm", "3pm", "4pm", "5pm", "6pm", "7pm", "8pm", "9pm", "10pm",
        "5:30am", "6:30am", "7:30am", "8:30am", "9:30am", "10:30am",
        "5:30pm", "6:30pm", "7:30pm", "8:30pm", "9:30pm", "noon", "midnight"
    ]
}


# ============================================
# CANCEL_ALL CLASS TEMPLATES (MUST have "all"/"every"/"everything")
# ============================================

CANCEL_ALL_TEMPLATES = [
    # Direct commands
    "{verb} all reminders",
    "{verb} all my reminders",
    "{verb} all the reminders",
    "{verb} every reminder",
    "{verb} everything",
    "{verb} all of them",

    # With "I want to"
    "I want to {verb} all reminders",
    "I want to {verb} all my reminders",

    # With "please"
    "please {verb} all reminders",
    "please {verb} all my reminders",

    # With "can you"
    "can you {verb} all reminders",
    "can you {verb} all my reminders",

    # With "just"
    "just {verb} all reminders",
    "just {verb} all my reminders",

    # Variations
    "get rid of all reminders",
    "get rid of all my reminders",
    "no more reminders",

    # With alarm/alert/notification
    "{verb} all alarms",
    "{verb} all alerts",
    "{verb} all notifications",

    # Active/scheduled/recurring
    "{verb} all active reminders",
    "{verb} all scheduled reminders",
    "{verb} all pending reminders",
    "{verb} all recurring reminders",
]

CANCEL_ALL_VERBS = ["cancel", "delete", "stop", "remove", "clear", "turn off", "disable", "end"]


# ============================================
# CANCEL_SPECIFIC CLASS TEMPLATES (NO "all"/"every")
# ============================================

CANCEL_SPECIFIC_TEMPLATES = [
    # "my X reminder"
    "{verb} my {topic} reminder",
    "{verb} the {topic} reminder",
    "{verb} {topic} reminder",

    # "reminder to X"
    "{verb} the reminder to {task}",
    "{verb} my reminder to {task}",
    "{verb} reminder to {task}",

    # "I don't want/need"
    "I don't want the {topic} reminder anymore",
    "I don't need the {topic} reminder",
    "I don't want the {topic} reminder",
    "I don't need the {topic} reminder anymore",
    "no more {topic} reminder",
    "no more {topic} reminders",
    "no need for {topic} reminder",

    # "stop reminding me"
    "stop reminding me about {topic}",
    "stop reminding me to {task}",
    "don't remind me about {topic} anymore",
    "don't remind me to {task}",

    # "I no longer need"
    "I no longer need the {topic} reminder",

    # "turn off"
    "turn off my {topic} reminder",
    "turn off the {topic} reminder",
    "turn off {topic} reminder",

    # With "that"
    "{verb} that {topic} reminder",

    # With "please"
    "please {verb} {topic} reminder",
    "please {verb} the {topic} reminder",

    # With "can you"
    "can you {verb} the {topic} reminder",
    "could you {verb} the {topic} reminder",

    # "I want to"
    "I want to {verb} the {topic} reminder",
    "I'd like to {verb} the {topic} reminder",

    # Special patterns
    "the {topic} reminder can be cancelled",
    "disable {topic} reminder",
    "deactivate {topic} reminder",
]

CANCEL_SPECIFIC_VERBS = ["cancel", "delete", "stop", "remove"]

CANCEL_SPECIFIC_TOPICS = [
    "water", "medicine", "exercise", "gym", "workout", "meeting", "call",
    "lunch", "dinner", "breakfast", "sleep", "wake up", "break", "stretch",
    "walk", "email", "bills", "rent", "grocery", "laundry", "vitamins",
    "yoga", "meditation", "reading", "study", "homework", "report",
    "presentation", "appointment", "doctor", "dentist", "interview",
    "morning", "evening", "night", "afternoon", "daily", "hourly",
    "hydration", "posture", "blink", "breathing", "snack", "coffee", "tea"
]

CANCEL_SPECIFIC_TASKS = [
    "drink water", "take medicine", "call mom", "call dad", "exercise",
    "go to gym", "wake up", "eat lunch", "eat dinner", "take a break",
    "stretch", "stand up", "check email", "attend meeting", "pay bills",
    "buy groceries", "water plants", "feed pet", "take vitamins", "study",
    "read", "meditate", "practice yoga", "go for run", "charge phone"
]


# ============================================
# UNCLEAR CLASS TEMPLATES
# ============================================

UNCLEAR_DATA = {
    "greetings": [
        "Hello", "Hi", "Hey", "Good morning", "Good afternoon", "Good evening",
        "Good night", "Hi there", "Hey there", "Hello there", "Howdy", "Yo",
        "What's up", "Wassup", "How are you", "How's it going", "How are you doing",
        "Greetings", "Hiya", "Heya", "Morning", "Evening", "Sup", "Hey hey",
        "Hello hello", "Hi hi"
    ],

    "single_words": [
        "Keys", "Wallet", "Phone", "Password", "Reminder", "Meeting", "Medicine",
        "Water", "Exercise", "Call", "Mom", "Dad", "Work", "Home", "Office",
        "Car", "Bike", "Food", "Lunch", "Dinner", "Breakfast", "Time", "Date",
        "Yes", "No", "Maybe", "Okay", "OK", "Sure", "Alright", "Fine", "Good",
        "Help", "Please", "Thanks", "Sorry", "What", "Why", "How", "When",
        "Where", "Who", "Stop", "Start", "Cancel", "Delete", "Save", "Find"
    ],

    "incomplete": [
        "I want to", "Can you", "Please", "The thing", "My", "Um", "Uh",
        "So", "Well", "Actually", "I think", "I need", "I have", "It's",
        "There is", "Let me", "I was", "I am", "You know", "Like",
        "I put my", "Where is", "Remind me", "Cancel", "Set a", "The password",
        "My keys", "In the", "At 5", "Every", "I left", "I kept", "Find my",
        "Search for", "Look for", "Tell me", "Show me", "What about", "How about",
        "Can I", "Should I", "Will you", "Would you", "Could you"
    ],

    "random": [
        "The weather is nice", "I like pizza", "What a beautiful day",
        "This is interesting", "I'm tired", "Just thinking", "Never mind",
        "Forget it", "Whatever", "Nothing", "I'm bored", "This is fun",
        "That's cool", "Sounds good", "I see", "Got it", "Makes sense",
        "I understand", "Fair enough", "No problem", "All good", "It's fine",
        "The sky is blue", "I love music", "Nice weather today",
        "I had coffee", "The food was good", "Traffic is bad", "I'm hungry",
        "I'm sleepy", "I'm happy", "That's funny", "How interesting"
    ],

    "gibberish": [
        "Asdf", "Qwerty", "Xyz", "Abc", "Hmm", "Uh huh", "Mmm", "Huh",
        "Blah", "Test", "Testing", "One two three", "Random", "Stuff",
        "Thing", "Something", "Anything", "La la la", "Blah blah",
        "Zzz", "Aaa", "Oops", "Uhh"
    ],

    "vague_questions": [
        "What do you think?", "Is it possible?", "Can you help?",
        "What should I do?", "How does it work?", "Is that right?",
        "Really?", "Are you sure?", "What?", "Huh?", "Why?", "How?",
        "When?", "Where?", "Who?", "Which one?", "What now?", "And then?",
        "So what?", "Now what?", "What else?", "Anything else?", "Is that all?",
        "What's next?", "What happened?", "Why is that?", "How come?"
    ],

    "conversational": [
        "Thank you", "Thanks", "Great", "Perfect", "Good", "Nice", "Cool",
        "Awesome", "Got it", "Understood", "I see", "Okay then", "Alright then",
        "Sounds good", "That's great", "That's nice", "Wonderful", "Amazing",
        "Fantastic", "Excellent", "Super", "Very good", "Well done",
        "No worries", "No problem", "It's okay", "That's fine", "Fair enough",
        "I agree", "I disagree", "Not sure", "I don't know", "Let me think",
        "Give me a moment", "One second", "Wait", "Hold on", "Just a minute"
    ],

    "partial": [
        "I", "My", "The", "A", "An", "To", "For", "In", "On", "At",
        "Re", "Rem", "Remi", "Can", "Canc", "Cance", "Sav", "Sear",
        "Whe", "Wher", "Wha", "Del", "Dele", "Delet", "Sto",
        "Set", "Add", "Cre", "Crea", "Fin"
    ]
}


# ============================================
# GENERATION FUNCTIONS
# ============================================

def generate_save_samples(target_count=2000):
    """Generate SAVE class samples with distinct patterns"""
    samples = set()

    # Pattern 1: Location storage (40%)
    location_templates = [
        "I {verb} my {item} in the {location}",
        "I {verb} my {item} on the {location}",
        "I {verb} the {item} in the {location}",
        "I {verb} the {item} on the {location}",
        "My {item} is in the {location}",
        "My {item} is on the {location}",
        "The {item} is in the {location}",
        "The {item} is kept in the {location}",
        "{item} is in the {location}",
        "I have {past_verb} my {item} in the {location}",
        "I have {past_verb} my {item} on the {location}",
        "I {verb} my {item} in {location}",
        "I {verb} my {item} at {location}",
        "My {item} is parked in {location}",
        "Put my {item} in the {location}",
    ]

    for template in location_templates:
        for verb in SAVE_DATA["location_verbs"]:
            for item in random.sample(SAVE_DATA["items"], min(30, len(SAVE_DATA["items"]))):
                for location in random.sample(SAVE_DATA["locations"], min(20, len(SAVE_DATA["locations"]))):
                    text = template.format(
                        verb=verb,
                        past_verb=random.choice(SAVE_DATA["location_verbs_past"]).split()[-1],
                        item=item,
                        location=location
                    )
                    samples.add((text, "save"))
                    if len(samples) >= target_count * 0.4:
                        break
                if len(samples) >= target_count * 0.4:
                    break
            if len(samples) >= target_count * 0.4:
                break
        if len(samples) >= target_count * 0.4:
            break

    # Pattern 2: Password/PIN storage (25%)
    password_templates = [
        "My {account} password is {password}",
        "The {account} password is {password}",
        "{account} password is {password}",
        "My {account} PIN is {pin}",
        "The {account} PIN is {pin}",
        "{account} PIN is {pin}",
        "The code for {account} is {password}",
        "Password for {account} is {password}",
        "PIN for {account} is {pin}",
        "My {account} code is {password}",
        "{account} login is {password}",
        "{account} credentials are {password}",
        "My {account} secret is {password}",
        "The {account} combination is {password}",
        "Access code for {account} is {password}",
    ]

    start_count = len(samples)
    for template in password_templates:
        for account in SAVE_DATA["accounts"]:
            for password in random.sample(SAVE_DATA["passwords"], 10):
                for pin in random.sample(SAVE_DATA["pins"], 5):
                    text = template.format(account=account, password=password, pin=pin)
                    samples.add((text, "save"))
                    if len(samples) - start_count >= target_count * 0.25:
                        break
                if len(samples) - start_count >= target_count * 0.25:
                    break
            if len(samples) - start_count >= target_count * 0.25:
                break
        if len(samples) - start_count >= target_count * 0.25:
            break

    # Pattern 3: Personal info (15%)
    info_templates = [
        "My {relation}'s {info} is {value}",
        "{relation}'s {info} is {value}",
        "My {info} is {value}",
        "The {info} for {relation} is {value}",
    ]

    start_count = len(samples)
    for template in info_templates:
        for relation in SAVE_DATA["relations"]:
            for info in SAVE_DATA["info_types"]:
                value = random.choice(SAVE_DATA["pins"]) + random.choice(["", "7890", "12345"])
                text = template.format(relation=relation, info=info, value=value)
                samples.add((text, "save"))
                if len(samples) - start_count >= target_count * 0.15:
                    break
            if len(samples) - start_count >= target_count * 0.15:
                break
        if len(samples) - start_count >= target_count * 0.15:
            break

    # Pattern 4: Events/schedules (10%)
    event_templates = [
        "The {event} is {time}",
        "My {event} is {time}",
        "{event} is {time}",
        "My {event} is on {date}",
        "The {event} is on {date}",
        "I have {event} {time}",
        "There is {event} {time}",
        "{event} at {time}",
        "Remember that {event} is {time}",
        "Note that {event} is {time}",
        "Don't forget {event} is {time}",
        "Keep in mind {event} is {time}",
    ]

    start_count = len(samples)
    for template in event_templates:
        for event in SAVE_DATA["events"]:
            for time in SAVE_DATA["time_expressions"]:
                for date in random.sample(SAVE_DATA["dates"], 5):
                    text = template.format(event=event, time=time, date=date)
                    samples.add((text, "save"))
                    if len(samples) - start_count >= target_count * 0.1:
                        break
                if len(samples) - start_count >= target_count * 0.1:
                    break
            if len(samples) - start_count >= target_count * 0.1:
                break
        if len(samples) - start_count >= target_count * 0.1:
            break

    # Pattern 5: Money/borrowed items (10%)
    money_templates = [
        "I owe {person} {amount} rupees",
        "I borrowed {amount} from {person}",
        "{person} owes me {amount}",
        "I lent {amount} to {person}",
        "{person} has my {item}",
        "I gave my {item} to {person}",
        "I borrowed the {item} from {person}",
        "I need to return the {item} to {person}",
    ]

    start_count = len(samples)
    for template in money_templates:
        for person in SAVE_DATA["persons"]:
            for amount in SAVE_DATA["amounts"]:
                for item in random.sample(SAVE_DATA["items"], 10):
                    text = template.format(person=person, amount=amount, item=item)
                    samples.add((text, "save"))
                    if len(samples) - start_count >= target_count * 0.1:
                        break
                if len(samples) - start_count >= target_count * 0.1:
                    break
            if len(samples) - start_count >= target_count * 0.1:
                break
        if len(samples) - start_count >= target_count * 0.1:
            break

    # Additional patterns to reach target
    additional_templates = [
        "The rent is due on the {date}",
        "Bill payment is on the {date}",
        "My car service is on {date}",
        "I took {medicine} at {time}",
        "I ate {meal} at {time}",
        "My blood group is {blood}",
        "My employee ID is EMP{num}",
        "My seat number is {num}{letter}",
        "I bought {item} from {store}",
        "I ordered {item} from {store}",
        "My size is {size}",
        "My allergies include {allergy}",
    ]

    while len(samples) < target_count:
        template = random.choice(additional_templates)
        try:
            text = template.format(
                date=random.choice(SAVE_DATA["dates"]),
                medicine=random.choice(SAVE_DATA["medicines"]),
                time=random.choice(SAVE_DATA["times_simple"]),
                meal=random.choice(SAVE_DATA["meals"]),
                blood=random.choice(SAVE_DATA["blood_types"]),
                num=random.randint(100, 999),
                letter=random.choice(["A", "B", "C", "D"]),
                item=random.choice(SAVE_DATA["items"]),
                store=random.choice(SAVE_DATA["stores"]),
                size=random.choice(SAVE_DATA["sizes"]),
                allergy=random.choice(SAVE_DATA["allergies"])
            )
            samples.add((text, "save"))
        except:
            continue

    return list(samples)[:target_count]


def generate_search_samples(target_count=2000):
    """Generate SEARCH class samples - must have question intent"""
    samples = set()

    # Pattern 1: Where questions (35%)
    where_templates = [
        "Where are my {item}?",
        "Where is my {item}?",
        "Where did I put my {item}?",
        "Where did I leave my {item}?",
        "Where did I keep my {item}?",
        "Where is the {item}?",
        "Where are the {item}?",
        "Where did I place my {item}?",
        "Where did I store my {item}?",
        "Where have I put my {item}?",
        "Where have I kept my {item}?",
        "Where can I find my {item}?",
        "Where would my {item} be?",
        "Do you know where my {item} is?",
        "Can you tell me where my {item} is?",
        "Where did I park my {item}?",
        "Where is my {item} located?",
        "My {item} is where?",
        "I put my {item} where?",
        "The {item} is where?",
    ]

    for template in where_templates:
        for item in SEARCH_DATA["items"]:
            text = template.format(item=item)
            samples.add((text, "search"))
            if len(samples) >= target_count * 0.35:
                break
        if len(samples) >= target_count * 0.35:
            break

    # Pattern 2: What questions (25%)
    what_templates = [
        "What is my {account} password?",
        "What is the {account} password?",
        "What was the {account} password?",
        "What is my {account} PIN?",
        "What is the code for {account}?",
        "What is {relation}'s {info}?",
        "What is my {info}?",
        "What time is the {event}?",
        "What time is my {event}?",
        "What is the {event} time?",
        "What did I save about {topic}?",
        "What did I note about {topic}?",
        "What did I tell you about {topic}?",
        "What do you know about {topic}?",
        "What do I have saved about {topic}?",
        "What was the {item} I saved?",
        "What information did I store about {topic}?",
    ]

    start_count = len(samples)
    for template in what_templates:
        for account in SEARCH_DATA["accounts"][:20]:
            for relation in SEARCH_DATA["relations"][:10]:
                for info in SEARCH_DATA["info_types"]:
                    for event in SEARCH_DATA["events"]:
                        for topic in SEARCH_DATA["topics"]:
                            for item in SEARCH_DATA["items"][:10]:
                                try:
                                    text = template.format(
                                        account=account, relation=relation,
                                        info=info, event=event, topic=topic, item=item
                                    )
                                    samples.add((text, "search"))
                                except:
                                    continue
                                if len(samples) - start_count >= target_count * 0.25:
                                    break
                            if len(samples) - start_count >= target_count * 0.25:
                                break
                        if len(samples) - start_count >= target_count * 0.25:
                            break
                    if len(samples) - start_count >= target_count * 0.25:
                        break
                if len(samples) - start_count >= target_count * 0.25:
                    break
            if len(samples) - start_count >= target_count * 0.25:
                break
        if len(samples) - start_count >= target_count * 0.25:
            break

    # Pattern 3: Did/Do questions (20%)
    did_do_templates = [
        "Did I {action}?",
        "Do I have {item}?",
        "Do I have any {event} today?",
        "Did I save {topic}?",
        "Do I have {event} tomorrow?",
        "Did I take my medicine?",
        "Did I pay the {bill}?",
        "Do I owe {person} money?",
        "Does {person} owe me money?",
        "Did I return the {item}?",
        "Do I need to {action}?",
        "Have I {action}?",
        "Did I already {action}?",
        "Am I supposed to {action}?",
        "Was I supposed to {action}?",
    ]

    start_count = len(samples)
    for template in did_do_templates:
        for action in SEARCH_DATA["actions"]:
            for item in SEARCH_DATA["items"][:15]:
                for event in SEARCH_DATA["events"]:
                    for topic in SEARCH_DATA["topics"]:
                        for bill in SEARCH_DATA["bills"]:
                            for person in SAVE_DATA["persons"][:10]:
                                try:
                                    text = template.format(
                                        action=action, item=item, event=event,
                                        topic=topic, bill=bill, person=person
                                    )
                                    samples.add((text, "search"))
                                except:
                                    continue
                                if len(samples) - start_count >= target_count * 0.2:
                                    break
                            if len(samples) - start_count >= target_count * 0.2:
                                break
                        if len(samples) - start_count >= target_count * 0.2:
                            break
                    if len(samples) - start_count >= target_count * 0.2:
                        break
                if len(samples) - start_count >= target_count * 0.2:
                    break
            if len(samples) - start_count >= target_count * 0.2:
                break
        if len(samples) - start_count >= target_count * 0.2:
            break

    # Pattern 4: Find/Search commands (20%)
    find_templates = [
        "Find my {item}",
        "Find where I put my {item}",
        "Find the {item}",
        "Search for my {item}",
        "Search for {topic}",
        "Look for my {item}",
        "Look up {topic}",
        "Search my saved {topic}",
        "Find my saved {topic}",
        "Look for {topic} in my notes",
        "Search {topic}",
        "Find {topic}",
        "Get my {item} location",
        "Retrieve {topic}",
        "Show me {topic}",
        "Tell me about {topic}",
        "Any info on {topic}?",
        "Anything about {topic}?",
    ]

    while len(samples) < target_count:
        template = random.choice(find_templates)
        try:
            text = template.format(
                item=random.choice(SEARCH_DATA["items"]),
                topic=random.choice(SEARCH_DATA["topics"])
            )
            samples.add((text, "search"))
        except:
            continue

    return list(samples)[:target_count]


def generate_reminder_samples(target_count=2200):
    """Generate REMINDER class samples - must have remind/alarm intent with time"""
    samples = set()

    # Pattern 1: Basic remind me (15%)
    basic_templates = [
        "Remind me to {task}",
        "Remind me to {task} please",
        "Please remind me to {task}",
        "Can you remind me to {task}",
        "I need a reminder to {task}",
        "Set a reminder to {task}",
        "Create a reminder to {task}",
        "Add a reminder to {task}",
        "Make a reminder to {task}",
        "I want a reminder to {task}",
        "Reminder to {task}",
        "{task} reminder",
        "Remind {task}",
        "Reminder {task}",
        "Alert me to {task}",
        "Notify me to {task}",
        "Don't let me forget to {task}",
        "Make sure I {task}",
        "Help me remember to {task}",
    ]

    for template in basic_templates:
        for task in REMINDER_DATA["tasks"]:
            text = template.format(task=task)
            samples.add((text, "reminder"))
            if len(samples) >= target_count * 0.15:
                break
        if len(samples) >= target_count * 0.15:
            break

    # Pattern 2: Duration based - "in X minutes/hours" (25%)
    duration_templates = [
        "Remind me to {task} in {num} {unit}",
        "Remind me to {task} after {num} {unit}",
        "In {num} {unit} remind me to {task}",
        "After {num} {unit} remind me to {task}",
        "Set a reminder for {num} {unit} to {task}",
        "Remind me in {num} {unit} to {task}",
        "Remind me after {num} {unit} to {task}",
        "{num} {unit} reminder to {task}",
        "Reminder in {num} {unit} to {task}",
        "{task} in {num} {unit}",
        "{task} after {num} {unit}",
        "Set reminder for {task} in {num} {unit}",
        "Create reminder to {task} in {num} {unit}",
        "Set a reminder for {num} {unit} to {task}",
    ]

    start_count = len(samples)
    for template in duration_templates:
        for task in REMINDER_DATA["tasks"]:
            for num in REMINDER_DATA["numbers_small"]:
                for unit in REMINDER_DATA["units_minute"] + REMINDER_DATA["units_hour"]:
                    text = template.format(task=task, num=num, unit=unit)
                    samples.add((text, "reminder"))
                    if len(samples) - start_count >= target_count * 0.25:
                        break
                if len(samples) - start_count >= target_count * 0.25:
                    break
            if len(samples) - start_count >= target_count * 0.25:
                break
        if len(samples) - start_count >= target_count * 0.25:
            break

    # Pattern 3: Static time - "at X pm/am" (25%)
    static_templates = [
        "Remind me to {task} at {time}",
        "Remind me at {time} to {task}",
        "Set a reminder for {time} to {task}",
        "At {time} remind me to {task}",
        "Reminder at {time} to {task}",
        "{task} at {time}",
        "Set alarm for {time} to {task}",
        "Wake me up at {time}",
        "Wake me at {time}",
        "Alarm at {time}",
        "Set alarm for {time}",
        "Remind me to {task} at {hour} {period}",
        "Remind me at {hour} {period} to {task}",
    ]

    start_count = len(samples)
    for template in static_templates:
        for task in REMINDER_DATA["tasks"]:
            for time in REMINDER_DATA["full_times"]:
                for hour in REMINDER_DATA["times_12h"][:6]:
                    for period in REMINDER_DATA["periods"]:
                        try:
                            text = template.format(task=task, time=time, hour=hour, period=period)
                            samples.add((text, "reminder"))
                        except:
                            continue
                        if len(samples) - start_count >= target_count * 0.25:
                            break
                    if len(samples) - start_count >= target_count * 0.25:
                        break
                if len(samples) - start_count >= target_count * 0.25:
                    break
            if len(samples) - start_count >= target_count * 0.25:
                break
        if len(samples) - start_count >= target_count * 0.25:
            break

    # Pattern 4: Recurring - "every X minutes/hours" (35%)
    recurring_templates = [
        "Remind me to {task} every {num} {unit}",
        "Remind me every {num} {unit} to {task}",
        "Every {num} {unit} remind me to {task}",
        "Set recurring reminder to {task} every {num} {unit}",
        "Recurring reminder every {num} {unit} to {task}",
        "{task} every {num} {unit}",
        "Every {num} {unit} {task}",
        "Repeat reminder to {task} every {num} {unit}",
        "Set repeating reminder every {num} {unit} for {task}",
        "Remind me to {task} every {unit}",
        "Every {unit} remind me to {task}",
        "{task} reminder every {num} {unit}",
        "Recurring {task} every {num} {unit}",
    ]

    while len(samples) < target_count:
        template = random.choice(recurring_templates)
        task = random.choice(REMINDER_DATA["tasks"])
        num = random.choice(REMINDER_DATA["numbers_large"])
        unit = random.choice(REMINDER_DATA["units_minute"] + REMINDER_DATA["units_hour"])
        text = template.format(task=task, num=num, unit=unit)
        samples.add((text, "reminder"))

    return list(samples)[:target_count]


def generate_cancel_all_samples(target_count=1400):
    """Generate CANCEL_ALL samples - MUST contain 'all'/'every'/'everything'"""
    samples = set()

    for template in CANCEL_ALL_TEMPLATES:
        for verb in CANCEL_ALL_VERBS:
            text = template.format(verb=verb)
            samples.add((text, "cancel_all"))
            # Add uppercase version
            samples.add((text.upper(), "cancel_all"))
            # Add lowercase version
            samples.add((text.lower(), "cancel_all"))
            # Add capitalized version
            samples.add((text.capitalize(), "cancel_all"))

    # Add more variations to reach target
    extra_templates = [
        "I want to {verb} all reminders",
        "I want to {verb} all my reminders",
        "I need to {verb} all reminders",
        "{verb} all of my reminders",
        "{verb} every single reminder",
        "I'd like to {verb} all reminders",
        "please {verb} all reminders",
        "just {verb} all the reminders",
        "can you please {verb} all reminders",
        "would you {verb} all my reminders",
        "{verb} all reminders please",
        "{verb} all my reminders please",
        "I don't want any reminders",
        "remove all pending reminders",
        "stop all scheduled reminders",
        "{verb} all existing reminders",
    ]

    while len(samples) < target_count:
        template = random.choice(extra_templates)
        verb = random.choice(CANCEL_ALL_VERBS)
        text = template.format(verb=verb)
        samples.add((text, "cancel_all"))
        samples.add((text.upper(), "cancel_all"))
        samples.add((text.lower(), "cancel_all"))

    return list(samples)[:target_count]


def generate_cancel_specific_samples(target_count=1800):
    """Generate CANCEL_SPECIFIC samples - NO 'all'/'every', has specific topic"""
    samples = set()

    for template in CANCEL_SPECIFIC_TEMPLATES:
        for verb in CANCEL_SPECIFIC_VERBS:
            for topic in CANCEL_SPECIFIC_TOPICS:
                for task in CANCEL_SPECIFIC_TASKS[:15]:
                    try:
                        text = template.format(verb=verb, topic=topic, task=task)
                        samples.add((text, "cancel_specific"))
                    except:
                        continue
                    if len(samples) >= target_count:
                        break
                if len(samples) >= target_count:
                    break
            if len(samples) >= target_count:
                break
        if len(samples) >= target_count:
            break

    # Fill remaining with variations
    while len(samples) < target_count:
        template = random.choice(CANCEL_SPECIFIC_TEMPLATES)
        verb = random.choice(CANCEL_SPECIFIC_VERBS)
        topic = random.choice(CANCEL_SPECIFIC_TOPICS)
        task = random.choice(CANCEL_SPECIFIC_TASKS)
        try:
            text = template.format(verb=verb, topic=topic, task=task)
            samples.add((text, "cancel_specific"))
        except:
            continue

    return list(samples)[:target_count]


def generate_unclear_samples(target_count=1600):
    """Generate UNCLEAR samples - ambiguous, incomplete, or unrelated"""
    samples = set()

    # Add all variations from categories
    for greeting in UNCLEAR_DATA["greetings"]:
        samples.add((greeting, "unclear"))
        samples.add((greeting.lower(), "unclear"))
        samples.add((greeting.upper(), "unclear"))

    for word in UNCLEAR_DATA["single_words"]:
        samples.add((word, "unclear"))
        samples.add((word.lower(), "unclear"))

    for incomplete in UNCLEAR_DATA["incomplete"]:
        samples.add((incomplete, "unclear"))

    for random_text in UNCLEAR_DATA["random"]:
        samples.add((random_text, "unclear"))

    for gibberish in UNCLEAR_DATA["gibberish"]:
        samples.add((gibberish, "unclear"))
        samples.add((gibberish.lower(), "unclear"))

    for question in UNCLEAR_DATA["vague_questions"]:
        samples.add((question, "unclear"))

    for conv in UNCLEAR_DATA["conversational"]:
        samples.add((conv, "unclear"))
        samples.add((conv.lower(), "unclear"))

    for partial in UNCLEAR_DATA["partial"]:
        samples.add((partial, "unclear"))

    # Fill remaining with random combinations
    all_unclear = (
        UNCLEAR_DATA["greetings"] +
        UNCLEAR_DATA["single_words"] +
        UNCLEAR_DATA["incomplete"] +
        UNCLEAR_DATA["random"] +
        UNCLEAR_DATA["gibberish"] +
        UNCLEAR_DATA["vague_questions"] +
        UNCLEAR_DATA["conversational"] +
        UNCLEAR_DATA["partial"]
    )

    while len(samples) < target_count:
        text = random.choice(all_unclear)
        samples.add((text, "unclear"))
        samples.add((text.lower(), "unclear"))
        if random.random() > 0.5:
            samples.add((text.upper(), "unclear"))

    return list(samples)[:target_count]


def validate_no_overlap(samples):
    """Validate that samples don't have patterns from wrong classes"""
    issues = []

    for text, label in samples:
        text_lower = text.lower()

        # CANCEL_ALL should have "all" or "every" or "everything"
        if label == "cancel_all":
            if not any(word in text_lower for word in ["all", "every", "everything"]):
                issues.append(f"cancel_all missing 'all/every': {text}")

        # CANCEL_SPECIFIC should NOT have "all" or "every"
        if label == "cancel_specific":
            if any(word in text_lower for word in [" all ", "all ", " all", " every ", "every ", " every", "everything"]):
                issues.append(f"cancel_specific has 'all/every': {text}")

        # REMINDER should have remind-related words
        if label == "reminder":
            reminder_words = ["remind", "reminder", "alarm", "alert", "notify", "wake"]
            if not any(word in text_lower for word in reminder_words):
                # Check for implicit patterns
                if not any(pattern in text_lower for pattern in ["every", " in ", " at ", " after "]):
                    issues.append(f"reminder missing remind words: {text}")

        # SAVE should NOT have question marks or "remind"
        if label == "save":
            if "?" in text or "remind" in text_lower:
                issues.append(f"save has question mark or remind: {text}")

    return issues


def split_data(all_samples, train_ratio=0.70, val_ratio=0.15, test_ratio=0.15):
    """Split samples into train/val/test sets maintaining class balance"""
    random.shuffle(all_samples)

    # Group by label
    by_label = {}
    for text, label in all_samples:
        if label not in by_label:
            by_label[label] = []
        by_label[label].append((text, label))

    train_data = []
    val_data = []
    test_data = []

    # Split each class proportionally
    for label, samples in by_label.items():
        random.shuffle(samples)
        n = len(samples)
        train_end = int(n * train_ratio)
        val_end = train_end + int(n * val_ratio)

        train_data.extend(samples[:train_end])
        val_data.extend(samples[train_end:val_end])
        test_data.extend(samples[val_end:])

    # Shuffle final datasets
    random.shuffle(train_data)
    random.shuffle(val_data)
    random.shuffle(test_data)

    return train_data, val_data, test_data


def save_to_csv(data, filepath):
    """Save data to CSV file"""
    with open(filepath, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['text', 'label'])
        for text, label in data:
            writer.writerow([text, label])
    print(f"Saved {len(data)} samples to {filepath}")


def main():
    print("=" * 60)
    print("Enhanced Training Data Generation v2")
    print("=" * 60)

    # Generate samples for each class
    print("\nGenerating samples...")

    save_samples = generate_save_samples(2000)
    print(f"  save: {len(save_samples)} samples")

    search_samples = generate_search_samples(2000)
    print(f"  search: {len(search_samples)} samples")

    reminder_samples = generate_reminder_samples(2200)
    print(f"  reminder: {len(reminder_samples)} samples")

    cancel_all_samples = generate_cancel_all_samples(1400)
    print(f"  cancel_all: {len(cancel_all_samples)} samples")

    cancel_specific_samples = generate_cancel_specific_samples(1800)
    print(f"  cancel_specific: {len(cancel_specific_samples)} samples")

    unclear_samples = generate_unclear_samples(1600)
    print(f"  unclear: {len(unclear_samples)} samples")

    # Combine all samples
    all_samples = (
        save_samples +
        search_samples +
        reminder_samples +
        cancel_all_samples +
        cancel_specific_samples +
        unclear_samples
    )

    print(f"\nTotal samples: {len(all_samples)}")

    # Remove duplicates
    unique_samples = list(set(all_samples))
    print(f"Unique samples: {len(unique_samples)}")

    # Validate samples
    print("\nValidating samples...")
    issues = validate_no_overlap(unique_samples)
    if issues:
        print(f"Found {len(issues)} potential issues (first 10):")
        for issue in issues[:10]:
            print(f"  - {issue}")
    else:
        print("No overlapping pattern issues found!")

    # Split data
    print("\nSplitting data...")
    train_data, val_data, test_data = split_data(unique_samples)

    print(f"  Train: {len(train_data)} samples")
    print(f"  Validation: {len(val_data)} samples")
    print(f"  Test: {len(test_data)} samples")

    # Save to CSV files
    print("\nSaving to CSV files...")

    save_to_csv(train_data, '../data/train/intent_train.csv')
    save_to_csv(val_data, '../data/validation/intent_val.csv')
    save_to_csv(test_data, '../data/test/intent_test.csv')

    # Print class distribution
    print("\nClass distribution:")
    for dataset_name, dataset in [("Train", train_data), ("Val", val_data), ("Test", test_data)]:
        print(f"\n  {dataset_name}:")
        labels = [label for _, label in dataset]
        for label in ["save", "search", "reminder", "cancel_all", "cancel_specific", "unclear"]:
            count = labels.count(label)
            pct = count / len(labels) * 100
            print(f"    {label}: {count} ({pct:.1f}%)")

    print("\n" + "=" * 60)
    print("Data generation complete!")
    print("=" * 60)


if __name__ == '__main__':
    main()
