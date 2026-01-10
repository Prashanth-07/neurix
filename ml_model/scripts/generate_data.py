"""
Generate training data for Intent Classification Model
Outputs: train/val/test CSV files with ~10,000 samples
"""

import csv
import random
import os

# ============================================
# DATA TEMPLATES
# ============================================

# === SAVE CLASS (1800 samples) ===
SAVE_TEMPLATES = {
    "location_storage": [
        "I put my {item} in the {location}",
        "I left my {item} on the {location}",
        "I kept my {item} in the {location}",
        "I placed my {item} on the {location}",
        "I stored my {item} in the {location}",
        "My {item} is in the {location}",
        "My {item} is on the {location}",
        "The {item} is in the {location}",
        "I put the {item} in the {location}",
        "I left the {item} on the {location}",
        "{item} is in the {location}",
        "I have put my {item} in the {location}",
        "I have left my {item} on the {location}",
        "I have kept my {item} in the {location}",
        "I parked my {item} in {location}",
        "I parked my {item} at {location}",
        "My {item} is parked in {location}",
        "The {item} is kept in the {location}",
        "I have stored the {item} in {location}",
        "Put my {item} in the {location}",
    ],
    "items": [
        "keys", "wallet", "phone", "bag", "laptop", "glasses", "watch", "charger",
        "headphones", "earphones", "airpods", "umbrella", "jacket", "coat", "shoes",
        "passport", "documents", "papers", "book", "notebook", "pen", "pencil",
        "medicine", "tablets", "pills", "water bottle", "lunch box", "backpack",
        "purse", "credit card", "debit card", "ID card", "driving license",
        "car keys", "house keys", "office keys", "bike keys", "remote", "TV remote",
        "mouse", "keyboard", "cable", "adapter", "power bank", "camera", "tablet",
        "iPad", "sunglasses", "ring", "necklace", "bracelet", "earrings", "toolbox"
    ],
    "locations": [
        "drawer", "table", "desk", "shelf", "cabinet", "cupboard", "wardrobe",
        "closet", "bedroom", "kitchen", "bathroom", "living room", "office",
        "car", "bag", "backpack", "purse", "pocket", "nightstand", "bedside table",
        "dining table", "coffee table", "counter", "rack", "hook", "box", "safe",
        "locker", "garage", "basement", "attic", "balcony", "garden", "parking lot",
        "lot A", "lot B", "lot C", "parking spot 5", "second floor", "top shelf",
        "bottom drawer", "left drawer", "right drawer", "middle shelf", "front pocket",
        "side pocket", "main compartment", "filing cabinet", "storage room", "guest room"
    ],

    "password_templates": [
        "My {account} password is {password}",
        "The {account} password is {password}",
        "{account} password is {password}",
        "My {account} PIN is {pin}",
        "The {account} PIN is {pin}",
        "{account} PIN is {pin}",
        "The code for {account} is {password}",
        "My {account} code is {password}",
        "{account} login is {password}",
        "Password for {account} is {password}",
        "PIN for {account} is {pin}",
        "The {account} combination is {password}",
        "My {account} secret is {password}",
        "{account} credentials are {password}",
        "Access code for {account} is {password}",
    ],
    "accounts": [
        "Netflix", "Amazon", "Gmail", "email", "Facebook", "Instagram", "Twitter",
        "LinkedIn", "WiFi", "router", "bank", "ATM", "credit card", "debit card",
        "phone", "laptop", "computer", "tablet", "iPad", "safe", "locker", "door",
        "garage", "office", "alarm", "security", "Spotify", "Apple", "Google",
        "YouTube", "Hotstar", "Prime Video", "Disney", "Uber", "Zomato", "Swiggy",
        "Paytm", "PhonePe", "GPay", "net banking", "trading", "Zerodha", "work email",
        "personal email", "home WiFi", "office WiFi", "guest WiFi", "building gate"
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

    "info_templates": [
        "My {relation}'s {info_type} is {value}",
        "{relation}'s {info_type} is {value}",
        "The {info_type} for {relation} is {value}",
        "My {info_type} is {value}",
        "The {event} is {time_info}",
        "My {event} is {time_info}",
        "{event} is scheduled for {time_info}",
        "{event} at {time_info}",
        "Remember that {event} is {time_info}",
        "Note that {event} is {time_info}",
        "Don't forget {event} is {time_info}",
        "Keep in mind {event} is {time_info}",
        "I have {event} {time_info}",
        "There is {event} {time_info}",
        "My {event} is on {day}",
    ],
    "relations": [
        "mom", "dad", "mother", "father", "brother", "sister", "wife", "husband",
        "son", "daughter", "uncle", "aunt", "grandma", "grandpa", "friend", "boss",
        "colleague", "neighbor", "doctor", "dentist", "lawyer", "accountant", "teacher"
    ],
    "info_types": [
        "phone number", "number", "birthday", "anniversary", "address", "email"
    ],
    "events": [
        "meeting", "appointment", "interview", "call", "flight", "train", "bus",
        "doctor appointment", "dentist appointment", "haircut", "reservation",
        "booking", "checkout", "check-in", "deadline", "submission", "presentation",
        "conference", "webinar", "class", "lecture", "exam", "test", "project review"
    ],
    "time_infos": [
        "at 9am", "at 10am", "at 11am", "at 12pm", "at 1pm", "at 2pm", "at 3pm",
        "at 4pm", "at 5pm", "at 6pm", "at 7pm", "at 8pm", "at 9pm", "tomorrow",
        "tomorrow morning", "tomorrow evening", "next week", "next Monday",
        "next Tuesday", "on Friday", "on Saturday", "on Sunday", "this weekend"
    ],
    "days": [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
        "January 15", "February 20", "March 10", "April 5", "May 25", "June 30",
        "the 5th", "the 10th", "the 15th", "the 20th", "the 25th", "the 1st"
    ],

    "direct_statements": [
        "I owe {person} {amount} rupees",
        "I borrowed {amount} from {person}",
        "{person} owes me {amount}",
        "I lent {amount} to {person}",
        "I need to return the {item} to {person}",
        "I borrowed the {item} from {person}",
        "{person} has my {item}",
        "I gave my {item} to {person}",
        "The rent is due on the {day}",
        "Bill payment is on the {day}",
        "My car service is on {day}",
        "I took {medicine} at {time}",
        "I ate {meal} at {time}",
        "My blood group is {blood_type}",
        "My employee ID is {id}",
        "My seat number is {seat}",
        "I bought {item} from {store}",
        "I ordered {item} from {store}",
        "My size is {size}",
        "My allergies include {allergy}",
    ],
    "persons": [
        "John", "Sarah", "Mike", "David", "Emma", "Lisa", "Tom", "Anna", "James",
        "Mary", "Robert", "Jennifer", "Chris", "Amy", "Daniel", "Rachel", "mom",
        "dad", "brother", "sister", "friend", "colleague", "roommate", "neighbor"
    ],
    "amounts": [
        "100", "200", "500", "1000", "1500", "2000", "5000", "10000", "50", "250"
    ],
    "medicines": [
        "medicine", "paracetamol", "aspirin", "vitamins", "antibiotics", "tablets",
        "cough syrup", "eye drops", "pain killer", "insulin", "blood pressure medicine"
    ],
    "meals": [
        "breakfast", "lunch", "dinner", "snacks", "brunch", "food", "meal"
    ],
    "times": [
        "8am", "9am", "10am", "12pm", "1pm", "2pm", "6pm", "7pm", "8pm", "9pm"
    ],
    "blood_types": [
        "O positive", "O negative", "A positive", "A negative", "B positive",
        "B negative", "AB positive", "AB negative"
    ],
    "stores": [
        "Amazon", "Flipkart", "Myntra", "BigBasket", "Swiggy", "Zomato", "mall",
        "supermarket", "grocery store", "pharmacy", "online", "eBay"
    ],
    "sizes": ["small", "medium", "large", "XL", "XXL", "S", "M", "L", "32", "34", "36", "38", "40"],
    "allergies": ["peanuts", "dairy", "gluten", "eggs", "shellfish", "dust", "pollen"]
}

# === SEARCH CLASS (1800 samples) ===
SEARCH_TEMPLATES = {
    "where_questions": [
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
    ],
    "items": [
        "keys", "wallet", "phone", "bag", "laptop", "glasses", "watch", "charger",
        "headphones", "earphones", "umbrella", "jacket", "passport", "documents",
        "book", "notebook", "medicine", "water bottle", "backpack", "purse",
        "credit card", "ID card", "car keys", "house keys", "remote", "mouse",
        "keyboard", "cable", "power bank", "camera", "tablet", "sunglasses",
        "car", "bike", "scooter", "vehicle"
    ],

    "what_questions": [
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
        "What was the {item} I saved?",
        "What did I save about {topic}?",
        "What did I note about {topic}?",
        "What information did I store about {topic}?",
        "What did I tell you about {topic}?",
        "What do I have saved about {topic}?",
    ],
    "accounts": [
        "Netflix", "Amazon", "Gmail", "email", "WiFi", "bank", "ATM", "phone",
        "laptop", "safe", "locker", "door", "garage", "office", "Spotify", "Apple"
    ],
    "relations": ["mom", "dad", "brother", "sister", "boss", "friend", "doctor"],
    "info": ["phone number", "number", "birthday", "address", "email"],
    "events": ["meeting", "appointment", "flight", "train", "interview", "call"],
    "topics": ["keys", "wallet", "password", "meeting", "flight", "appointment", "car"],

    "when_questions": [
        "When is {relation}'s {event}?",
        "When is my {event}?",
        "When is the {event}?",
        "When did I save {topic}?",
        "When is the deadline?",
        "When is the submission?",
        "When do I have {event}?",
        "When was my last {event}?",
    ],
    "event_types": ["birthday", "anniversary", "meeting", "appointment", "flight", "exam"],

    "did_do_questions": [
        "Did I {action}?",
        "Do I have {item}?",
        "Do I have any {event} today?",
        "Did I save {topic}?",
        "Do I have {event} tomorrow?",
        "Did I take my {medicine}?",
        "Did I pay the {bill}?",
        "Do I owe {person} money?",
        "Does {person} owe me money?",
        "Did I return the {item}?",
        "Do I need to {action}?",
        "Have I {action}?",
        "Did I already {action}?",
        "Am I supposed to {action}?",
        "Was I supposed to {action}?",
    ],
    "actions": [
        "pay the bill", "take medicine", "call mom", "submit the report",
        "attend the meeting", "book tickets", "return the book", "pay rent",
        "charge my phone", "lock the door", "turn off the stove", "feed the pet"
    ],
    "bills": ["electricity bill", "water bill", "phone bill", "internet bill", "rent", "EMI"],
    "medicine": ["medicine", "tablet", "vitamin", "pill"],

    "find_search_commands": [
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
        "What do you know about {topic}?",
        "Any info on {topic}?",
        "Anything about {topic}?",
        "Do you have {topic}?",
    ],

    "implicit_questions": [
        "I need to know my {account} password",
        "I forgot where I put my {item}",
        "I can't remember the {account} password",
        "I can't find my {item}",
        "Need the {account} code",
        "Looking for my {item}",
        "Trying to find my {item}",
        "I need {relation}'s number",
        "What about my {item}?",
        "My {item}?",
        "The {item} location?",
        "Tell me where my {item} are",
        "Show me where I kept my {item}",
    ],
}

# === REMINDER CLASS (2000 samples) ===
REMINDER_TEMPLATES = {
    "remind_me_basic": [
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
    ],
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

    "duration_based": [
        "Remind me to {task} in {number} {unit}",
        "Remind me to {task} after {number} {unit}",
        "In {number} {unit} remind me to {task}",
        "After {number} {unit} remind me to {task}",
        "Set a reminder for {number} {unit} to {task}",
        "Remind me in {number} {unit} to {task}",
        "Remind me after {number} {unit} to {task}",
        "{number} {unit} reminder to {task}",
        "Reminder in {number} {unit} to {task}",
        "{task} in {number} {unit}",
        "{task} after {number} {unit}",
        "Set reminder for {task} in {number} {unit}",
        "Create reminder to {task} in {number} {unit}",
    ],
    "numbers": ["1", "2", "3", "5", "10", "15", "20", "30", "45"],
    "units": ["minute", "minutes", "min", "mins", "hour", "hours", "hr", "hrs"],

    "static_time": [
        "Remind me to {task} at {time}",
        "Remind me at {time} to {task}",
        "Set a reminder for {time} to {task}",
        "At {time} remind me to {task}",
        "Reminder at {time} to {task}",
        "{task} at {time}",
        "Set alarm for {time} to {task}",
        "Remind me to {task} at {time} {period}",
        "Remind me at {time} {period} to {task}",
        "Wake me up at {time}",
        "Wake me at {time}",
        "Alarm at {time}",
        "Set alarm for {time}",
    ],
    "times": ["5", "6", "7", "8", "9", "10", "11", "12", "1", "2", "3", "4"],
    "periods": ["am", "AM", "pm", "PM", "in the morning", "in the evening", "in the afternoon", "at night"],
    "full_times": [
        "5am", "6am", "7am", "8am", "9am", "10am", "11am", "12pm",
        "1pm", "2pm", "3pm", "4pm", "5pm", "6pm", "7pm", "8pm", "9pm", "10pm",
        "5:30am", "6:30am", "7:30am", "8:30am", "9:30am", "10:30am",
        "5:30pm", "6:30pm", "7:30pm", "8:30pm", "9:30pm",
        "noon", "midnight"
    ],

    "recurring": [
        "Remind me to {task} every {number} {unit}",
        "Remind me every {number} {unit} to {task}",
        "Every {number} {unit} remind me to {task}",
        "Set recurring reminder to {task} every {number} {unit}",
        "Recurring reminder every {number} {unit} to {task}",
        "{task} every {number} {unit}",
        "Every {number} {unit} {task}",
        "Repeat reminder to {task} every {number} {unit}",
        "Set repeating reminder every {number} {unit} for {task}",
        "Remind me to {task} every {unit}",
        "Every {unit} remind me to {task}",
        "{task} reminder every {number} {unit}",
        "Recurring {task} every {number} {unit}",
    ],
    "recurring_units": ["minute", "minutes", "min", "mins", "hour", "hours", "hr", "hrs"],
    "recurring_numbers": ["1", "2", "3", "5", "10", "15", "20", "30", "45", "60", "90"],

    "casual_short": [
        "Reminder {task}",
        "{task} reminder",
        "Remind {task}",
        "Alert me to {task}",
        "Notify me to {task}",
        "Don't let me forget to {task}",
        "Make sure I {task}",
        "Help me remember to {task}",
    ],
}

# === CANCEL_ALL CLASS (1200 samples) ===
CANCEL_ALL_TEMPLATES = {
    "patterns": [
        "Cancel all reminders",
        "Delete all reminders",
        "Stop all reminders",
        "Remove all reminders",
        "Clear all reminders",
        "Turn off all reminders",
        "Disable all reminders",
        "End all reminders",
        "Cancel all my reminders",
        "Delete all my reminders",
        "Stop all my reminders",
        "Remove all my reminders",
        "Clear all my reminders",
        "Turn off all my reminders",
        "Disable all my reminders",
        "Cancel every reminder",
        "Delete every reminder",
        "Stop every reminder",
        "Remove every reminder",
        "Cancel all the reminders",
        "Delete all the reminders",
        "Stop all the reminders",
        "Remove all the reminders",
        "I want to cancel all reminders",
        "I want to delete all reminders",
        "I want to stop all reminders",
        "I want to remove all reminders",
        "Please cancel all reminders",
        "Please delete all reminders",
        "Please stop all reminders",
        "Please remove all reminders",
        "Can you cancel all reminders",
        "Can you delete all reminders",
        "Can you stop all reminders",
        "Can you remove all reminders",
        "Just cancel all reminders",
        "Just delete all reminders",
        "Just stop all reminders",
        "Just remove all reminders",
        "Get rid of all reminders",
        "Get rid of all my reminders",
        "Cancel everything",
        "Delete everything",
        "Stop everything",
        "Remove everything",
        "Clear everything",
        "No more reminders",
        "Stop all of them",
        "Cancel all of them",
        "Delete all of them",
        "Remove all of them",
        "Clear all of them",
        "I don't want any reminders",
        "Remove all alerts",
        "Cancel all alerts",
        "Stop all alerts",
        "Delete all alerts",
        "Clear all alerts",
        "Cancel all notifications",
        "Stop all notifications",
        "Turn off all notifications",
        "Cancel all alarms",
        "Delete all alarms",
        "Stop all alarms",
        "Remove all alarms",
        "Clear all alarms",
        "Cancel all active reminders",
        "Delete all active reminders",
        "Stop all active reminders",
        "Cancel all scheduled reminders",
        "Delete all scheduled reminders",
        "Stop all pending reminders",
        "Remove all pending reminders",
        "Cancel all recurring reminders",
        "Stop all recurring reminders",
        "Delete all recurring reminders",
    ],
}

# === CANCEL_SPECIFIC CLASS (1600 samples) ===
CANCEL_SPECIFIC_TEMPLATES = {
    "cancel_my_x_reminder": [
        "Cancel my {topic} reminder",
        "Delete my {topic} reminder",
        "Stop my {topic} reminder",
        "Remove my {topic} reminder",
        "Turn off my {topic} reminder",
        "Disable my {topic} reminder",
        "Cancel the {topic} reminder",
        "Delete the {topic} reminder",
        "Stop the {topic} reminder",
        "Remove the {topic} reminder",
        "Turn off the {topic} reminder",
        "Cancel {topic} reminder",
        "Delete {topic} reminder",
        "Stop {topic} reminder",
        "Remove {topic} reminder",
    ],
    "topics": [
        "water", "medicine", "exercise", "gym", "workout", "meeting", "call",
        "lunch", "dinner", "breakfast", "sleep", "wake up", "break", "stretch",
        "walk", "email", "bills", "rent", "grocery", "laundry", "vitamins",
        "yoga", "meditation", "reading", "study", "homework", "report",
        "presentation", "appointment", "doctor", "dentist", "interview",
        "morning", "evening", "night", "afternoon", "daily", "hourly",
        "hydration", "posture", "blink", "breathing", "snack", "coffee", "tea"
    ],

    "cancel_reminder_to": [
        "Cancel the reminder to {task}",
        "Delete the reminder to {task}",
        "Stop the reminder to {task}",
        "Remove the reminder to {task}",
        "Cancel my reminder to {task}",
        "Delete my reminder to {task}",
        "Stop my reminder to {task}",
        "Remove my reminder to {task}",
        "Cancel reminder to {task}",
        "Delete reminder to {task}",
        "Stop reminder to {task}",
        "Remove reminder to {task}",
    ],
    "tasks": [
        "drink water", "take medicine", "call mom", "call dad", "exercise",
        "go to gym", "wake up", "eat lunch", "eat dinner", "take a break",
        "stretch", "stand up", "check email", "attend meeting", "pay bills",
        "buy groceries", "water plants", "feed pet", "take vitamins", "study",
        "read", "meditate", "practice yoga", "go for run", "charge phone"
    ],

    "dont_want_need": [
        "I don't want the {topic} reminder anymore",
        "I don't need the {topic} reminder",
        "I don't want the {topic} reminder",
        "I don't need the {topic} reminder anymore",
        "Don't remind me about {topic} anymore",
        "Stop reminding me about {topic}",
        "Stop reminding me to {task}",
        "Don't remind me to {task}",
        "I don't need to be reminded about {topic}",
        "I don't want to be reminded about {topic}",
        "No more {topic} reminders",
        "No more {topic} reminder",
        "No need for {topic} reminder",
        "I no longer need the {topic} reminder",
        "Remove the {topic} one",
        "Cancel the {topic} one",
        "Stop the {topic} one",
        "Delete the {topic} one",
        "Turn off {topic} notifications",
        "Disable {topic} reminder",
        "Deactivate {topic} reminder",
    ],

    "variations": [
        "Cancel that {topic} reminder",
        "Delete that {topic} reminder",
        "Stop that {topic} reminder",
        "Remove that {topic} reminder",
        "The {topic} reminder can be cancelled",
        "Please cancel {topic} reminder",
        "Please stop {topic} reminder",
        "Please delete {topic} reminder",
        "Can you cancel the {topic} reminder",
        "Can you stop the {topic} reminder",
        "Can you delete the {topic} reminder",
        "Could you cancel the {topic} reminder",
        "Could you stop the {topic} reminder",
        "I'd like to cancel the {topic} reminder",
        "I want to cancel the {topic} reminder",
        "I want to stop the {topic} reminder",
        "I want to delete the {topic} reminder",
    ],
}

# === UNCLEAR CLASS (1600 samples) ===
UNCLEAR_TEMPLATES = {
    "greetings": [
        "Hello", "Hi", "Hey", "Good morning", "Good afternoon", "Good evening",
        "Good night", "Hi there", "Hey there", "Hello there", "Howdy", "Yo",
        "What's up", "Wassup", "How are you", "How's it going", "How are you doing",
        "Nice to meet you", "Greetings", "Hiya", "Heya", "Morning", "Evening",
        "Sup", "Hey hey", "Hello hello", "Hi hi"
    ],

    "single_words": [
        "Keys", "Wallet", "Phone", "Password", "Reminder", "Meeting", "Medicine",
        "Water", "Exercise", "Call", "Mom", "Dad", "Work", "Home", "Office",
        "Car", "Bike", "Food", "Lunch", "Dinner", "Breakfast", "Time", "Date",
        "Yes", "No", "Maybe", "Okay", "OK", "Sure", "Alright", "Fine", "Good",
        "Bad", "Help", "Please", "Thanks", "Sorry", "What", "Why", "How", "When",
        "Where", "Who", "Stop", "Start", "Cancel", "Delete", "Save", "Find"
    ],

    "incomplete_sentences": [
        "I want to", "Can you", "Please", "The thing", "My", "Um", "Uh",
        "So", "Well", "Actually", "I think", "I need", "I have", "It's",
        "There is", "Let me", "I was", "I am", "You know", "Like",
        "I put my", "Where is", "Remind me", "Cancel", "Set a", "The password",
        "My keys", "In the", "At 5", "Every", "I left", "I kept", "Find my",
        "Search for", "Look for", "Tell me", "Show me", "What about", "How about",
        "Can I", "Should I", "Will you", "Would you", "Could you"
    ],

    "random_unrelated": [
        "The weather is nice", "I like pizza", "What a beautiful day",
        "This is interesting", "I'm tired", "Just thinking", "Never mind",
        "Forget it", "Whatever", "Nothing", "I'm bored", "This is fun",
        "That's cool", "Sounds good", "I see", "Got it", "Makes sense",
        "I understand", "Fair enough", "No problem", "All good", "It's fine",
        "The sky is blue", "I love music", "Nice weather today",
        "I had coffee", "The food was good", "Traffic is bad", "I'm hungry",
        "I'm sleepy", "I'm happy", "I'm sad", "That's funny", "How interesting"
    ],

    "gibberish_noise": [
        "Asdf", "Qwerty", "Xyz", "Abc", "Hmm", "Uh huh", "Mmm", "Huh",
        "Blah", "Test", "Testing", "One two three", "Random", "Stuff",
        "Thing", "Something", "Anything", "Whatever", "La la la", "Blah blah",
        "Zzz", "Aaa", "Bbb", "Ccc", "123", "321", "111", "Oops", "Uhh"
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
        "Sounds good", "That's great", "That's nice", "That's cool", "Wonderful",
        "Amazing", "Fantastic", "Excellent", "Super", "Very good", "Well done",
        "No worries", "No problem", "It's okay", "That's fine", "Fair enough",
        "I agree", "I disagree", "Not sure", "I don't know", "Let me think",
        "Give me a moment", "One second", "Wait", "Hold on", "Just a minute"
    ],

    "partial_truncated": [
        "I", "My", "The", "A", "An", "To", "For", "In", "On", "At",
        "Re", "Rem", "Remi", "Remin", "Can", "Canc", "Cance", "Sav", "Sear",
        "Whe", "Wher", "What", "Wha", "How", "Why", "Del", "Dele", "Delet",
        "Sto", "Stop", "Set", "Add", "Cre", "Crea", "Creat", "Fin", "Find"
    ],
}


# ============================================
# DATA GENERATION FUNCTIONS
# ============================================

def generate_save_samples(count=1800):
    """Generate save class samples"""
    samples = []

    # Location storage
    for _ in range(count // 4):
        template = random.choice(SAVE_TEMPLATES["location_storage"])
        item = random.choice(SAVE_TEMPLATES["items"])
        location = random.choice(SAVE_TEMPLATES["locations"])
        text = template.format(item=item, location=location)
        samples.append((text, "save"))

    # Password storage
    for _ in range(count // 4):
        template = random.choice(SAVE_TEMPLATES["password_templates"])
        account = random.choice(SAVE_TEMPLATES["accounts"])
        password = random.choice(SAVE_TEMPLATES["passwords"])
        pin = random.choice(SAVE_TEMPLATES["pins"])
        text = template.format(account=account, password=password, pin=pin)
        samples.append((text, "save"))

    # Info storage
    for _ in range(count // 4):
        template = random.choice(SAVE_TEMPLATES["info_templates"])
        try:
            text = template.format(
                relation=random.choice(SAVE_TEMPLATES["relations"]),
                info_type=random.choice(SAVE_TEMPLATES["info_types"]),
                value=random.choice(SAVE_TEMPLATES["pins"]) + random.choice(["", "7890", "12345"]),
                event=random.choice(SAVE_TEMPLATES["events"]),
                time_info=random.choice(SAVE_TEMPLATES["time_infos"]),
                day=random.choice(SAVE_TEMPLATES["days"])
            )
            samples.append((text, "save"))
        except KeyError:
            continue

    # Direct statements
    for _ in range(count // 4):
        template = random.choice(SAVE_TEMPLATES["direct_statements"])
        try:
            text = template.format(
                person=random.choice(SAVE_TEMPLATES["persons"]),
                amount=random.choice(SAVE_TEMPLATES["amounts"]),
                item=random.choice(SAVE_TEMPLATES["items"]),
                day=random.choice(SAVE_TEMPLATES["days"]),
                medicine=random.choice(SAVE_TEMPLATES["medicines"]),
                meal=random.choice(SAVE_TEMPLATES["meals"]),
                time=random.choice(SAVE_TEMPLATES["times"]),
                blood_type=random.choice(SAVE_TEMPLATES["blood_types"]),
                id="EMP" + str(random.randint(100, 999)),
                seat=str(random.randint(1, 50)) + random.choice(["A", "B", "C", "D"]),
                store=random.choice(SAVE_TEMPLATES["stores"]),
                size=random.choice(SAVE_TEMPLATES["sizes"]),
                allergy=random.choice(SAVE_TEMPLATES["allergies"])
            )
            samples.append((text, "save"))
        except KeyError:
            continue

    return samples[:count]


def generate_search_samples(count=1800):
    """Generate search class samples"""
    samples = []

    # Where questions
    for _ in range(count // 4):
        template = random.choice(SEARCH_TEMPLATES["where_questions"])
        item = random.choice(SEARCH_TEMPLATES["items"])
        text = template.format(item=item)
        samples.append((text, "search"))

    # What questions
    for _ in range(count // 4):
        template = random.choice(SEARCH_TEMPLATES["what_questions"])
        try:
            text = template.format(
                account=random.choice(SEARCH_TEMPLATES["accounts"]),
                relation=random.choice(SEARCH_TEMPLATES["relations"]),
                info=random.choice(SEARCH_TEMPLATES["info"]),
                event=random.choice(SEARCH_TEMPLATES["events"]),
                item=random.choice(SEARCH_TEMPLATES["items"]),
                topic=random.choice(SEARCH_TEMPLATES["topics"])
            )
            samples.append((text, "search"))
        except KeyError:
            continue

    # Did/Do questions
    for _ in range(count // 4):
        template = random.choice(SEARCH_TEMPLATES["did_do_questions"])
        try:
            text = template.format(
                action=random.choice(SEARCH_TEMPLATES["actions"]),
                item=random.choice(SEARCH_TEMPLATES["items"]),
                event=random.choice(SEARCH_TEMPLATES["events"]),
                topic=random.choice(SEARCH_TEMPLATES["topics"]),
                medicine=random.choice(SEARCH_TEMPLATES["medicine"]),
                bill=random.choice(SEARCH_TEMPLATES["bills"]),
                person=random.choice(SAVE_TEMPLATES["persons"])
            )
            samples.append((text, "search"))
        except KeyError:
            continue

    # Find/Search commands
    for _ in range(count // 4):
        template = random.choice(SEARCH_TEMPLATES["find_search_commands"])
        try:
            text = template.format(
                item=random.choice(SEARCH_TEMPLATES["items"]),
                topic=random.choice(SEARCH_TEMPLATES["topics"])
            )
            samples.append((text, "search"))
        except KeyError:
            continue

    # Add implicit questions
    for template in SEARCH_TEMPLATES["implicit_questions"]:
        try:
            text = template.format(
                account=random.choice(SEARCH_TEMPLATES["accounts"]),
                item=random.choice(SEARCH_TEMPLATES["items"]),
                relation=random.choice(SEARCH_TEMPLATES["relations"])
            )
            samples.append((text, "search"))
        except KeyError:
            continue

    return samples[:count]


def generate_reminder_samples(count=2000):
    """Generate reminder class samples"""
    samples = []

    # Basic reminders
    for _ in range(count // 5):
        template = random.choice(REMINDER_TEMPLATES["remind_me_basic"])
        task = random.choice(REMINDER_TEMPLATES["tasks"])
        text = template.format(task=task)
        samples.append((text, "reminder"))

    # Duration based
    for _ in range(count // 5):
        template = random.choice(REMINDER_TEMPLATES["duration_based"])
        task = random.choice(REMINDER_TEMPLATES["tasks"])
        number = random.choice(REMINDER_TEMPLATES["numbers"])
        unit = random.choice(REMINDER_TEMPLATES["units"])
        text = template.format(task=task, number=number, unit=unit)
        samples.append((text, "reminder"))

    # Static time
    for _ in range(count // 5):
        template = random.choice(REMINDER_TEMPLATES["static_time"])
        task = random.choice(REMINDER_TEMPLATES["tasks"])
        time = random.choice(REMINDER_TEMPLATES["full_times"])
        time_num = random.choice(REMINDER_TEMPLATES["times"])
        period = random.choice(REMINDER_TEMPLATES["periods"])
        try:
            text = template.format(task=task, time=time, period=period)
        except KeyError:
            text = template.format(task=task, time=time_num, period=period)
        samples.append((text, "reminder"))

    # Recurring
    for _ in range(count // 5):
        template = random.choice(REMINDER_TEMPLATES["recurring"])
        task = random.choice(REMINDER_TEMPLATES["tasks"])
        number = random.choice(REMINDER_TEMPLATES["recurring_numbers"])
        unit = random.choice(REMINDER_TEMPLATES["recurring_units"])
        text = template.format(task=task, number=number, unit=unit)
        samples.append((text, "reminder"))

    # Casual short
    for _ in range(count // 5):
        template = random.choice(REMINDER_TEMPLATES["casual_short"])
        task = random.choice(REMINDER_TEMPLATES["tasks"])
        text = template.format(task=task)
        samples.append((text, "reminder"))

    return samples[:count]


def generate_cancel_all_samples(count=1200):
    """Generate cancel_all class samples"""
    samples = []

    patterns = CANCEL_ALL_TEMPLATES["patterns"]

    # Repeat patterns to reach count
    while len(samples) < count:
        for pattern in patterns:
            samples.append((pattern, "cancel_all"))
            if len(samples) >= count:
                break

        # Add variations with different capitalizations
        for pattern in patterns:
            samples.append((pattern.lower(), "cancel_all"))
            if len(samples) >= count:
                break
            samples.append((pattern.upper(), "cancel_all"))
            if len(samples) >= count:
                break
            samples.append((pattern.capitalize(), "cancel_all"))
            if len(samples) >= count:
                break

    return samples[:count]


def generate_cancel_specific_samples(count=1600):
    """Generate cancel_specific class samples"""
    samples = []

    # Cancel my X reminder
    for _ in range(count // 4):
        template = random.choice(CANCEL_SPECIFIC_TEMPLATES["cancel_my_x_reminder"])
        topic = random.choice(CANCEL_SPECIFIC_TEMPLATES["topics"])
        text = template.format(topic=topic)
        samples.append((text, "cancel_specific"))

    # Cancel reminder to
    for _ in range(count // 4):
        template = random.choice(CANCEL_SPECIFIC_TEMPLATES["cancel_reminder_to"])
        task = random.choice(CANCEL_SPECIFIC_TEMPLATES["tasks"])
        text = template.format(task=task)
        samples.append((text, "cancel_specific"))

    # Don't want/need
    for _ in range(count // 4):
        template = random.choice(CANCEL_SPECIFIC_TEMPLATES["dont_want_need"])
        topic = random.choice(CANCEL_SPECIFIC_TEMPLATES["topics"])
        task = random.choice(CANCEL_SPECIFIC_TEMPLATES["tasks"])
        try:
            text = template.format(topic=topic, task=task)
        except KeyError:
            text = template.format(topic=topic)
        samples.append((text, "cancel_specific"))

    # Variations
    for _ in range(count // 4):
        template = random.choice(CANCEL_SPECIFIC_TEMPLATES["variations"])
        topic = random.choice(CANCEL_SPECIFIC_TEMPLATES["topics"])
        text = template.format(topic=topic)
        samples.append((text, "cancel_specific"))

    return samples[:count]


def generate_unclear_samples(count=1600):
    """Generate unclear class samples"""
    samples = []

    # Greetings
    for greeting in UNCLEAR_TEMPLATES["greetings"]:
        samples.append((greeting, "unclear"))
        samples.append((greeting.lower(), "unclear"))
        samples.append((greeting.upper(), "unclear"))

    # Single words
    for word in UNCLEAR_TEMPLATES["single_words"]:
        samples.append((word, "unclear"))
        samples.append((word.lower(), "unclear"))

    # Incomplete sentences
    for sentence in UNCLEAR_TEMPLATES["incomplete_sentences"]:
        samples.append((sentence, "unclear"))

    # Random unrelated
    for text in UNCLEAR_TEMPLATES["random_unrelated"]:
        samples.append((text, "unclear"))

    # Gibberish
    for text in UNCLEAR_TEMPLATES["gibberish_noise"]:
        samples.append((text, "unclear"))

    # Vague questions
    for text in UNCLEAR_TEMPLATES["vague_questions"]:
        samples.append((text, "unclear"))

    # Conversational
    for text in UNCLEAR_TEMPLATES["conversational"]:
        samples.append((text, "unclear"))

    # Partial truncated
    for text in UNCLEAR_TEMPLATES["partial_truncated"]:
        samples.append((text, "unclear"))

    # Fill remaining with random combinations
    while len(samples) < count:
        category = random.choice(list(UNCLEAR_TEMPLATES.keys()))
        text = random.choice(UNCLEAR_TEMPLATES[category])
        samples.append((text, "unclear"))

    return samples[:count]


def split_data(all_samples, train_ratio=0.70, val_ratio=0.15, test_ratio=0.15):
    """Split samples into train/val/test sets"""
    random.shuffle(all_samples)

    total = len(all_samples)
    train_end = int(total * train_ratio)
    val_end = train_end + int(total * val_ratio)

    train_data = all_samples[:train_end]
    val_data = all_samples[train_end:val_end]
    test_data = all_samples[val_end:]

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
    print("=" * 50)
    print("Generating Training Data")
    print("=" * 50)

    # Generate samples for each class
    print("\nGenerating samples...")

    save_samples = generate_save_samples(1800)
    print(f"  save: {len(save_samples)} samples")

    search_samples = generate_search_samples(1800)
    print(f"  search: {len(search_samples)} samples")

    reminder_samples = generate_reminder_samples(2000)
    print(f"  reminder: {len(reminder_samples)} samples")

    cancel_all_samples = generate_cancel_all_samples(1200)
    print(f"  cancel_all: {len(cancel_all_samples)} samples")

    cancel_specific_samples = generate_cancel_specific_samples(1600)
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
            print(f"    {label}: {count}")

    print("\n" + "=" * 50)
    print("Data generation complete!")
    print("=" * 50)


if __name__ == '__main__':
    main()
