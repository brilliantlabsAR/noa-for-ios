import urandom
import time

previous_prompt = 0

quries = [
    "Write a poem about love and loss, using metaphors and imagery to evoke emotion",
    "Create a song lyrics about chasing dreams and overcoming obstacles",
    "Generate a short story about a musician who discovers their true passion",
    "Write a script for a music video that tells a story of heartbreak and redemption",
    "Create a sonnet about the beauty of nature, using vivid imagery and rhyme",
    "Generate a monologue for a play about a struggling artist trying to make it in the music industry",
    "Write a song about the power of friendship and support",
    "Create a poem about the fleeting nature of time, using personification and allusion",
    "Generate a short poetry about a band that reunites after years apart",
    "Write a script for a musical about the rise and fall of a legendary musician",
    "Create a song lyrics about the beauty and the pain of falling in love",
    "Generate a monologue for a play about the struggles of being a musician",
    "Write a poem about the beauty of music, using vivid imagery and metaphor",
    "Create a song lyrics about the importance of being true to oneself",
    "Generate a short story about a musician who overcomes personal demons to find success",
    "Write a script for a music video that tells a story of self-discovery and empowerment",
    "Create a sonnet about the beauty of the stars and the night sky, using metaphor and imagery",
]

while True:
    while True:
        selected_prompt = urandom.randint(0, len(quries) - 1)
        if selected_prompt != previous_prompt:
            previous_prompt = selected_prompt
            break

    print(quries[selected_prompt])
    # print("foo")

    delay = urandom.randint(1, 5)
    # delay = urandom.randint(20, 30)
    time.sleep(delay)
