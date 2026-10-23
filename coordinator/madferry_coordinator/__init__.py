"""Daily coordinator that publishes Madeline Island Ferry schedule data as static JSON."""

SCHEMA_VERSION = 1
TIME_ZONE = "America/Chicago"
USER_AGENT = "MadFerryScheduleBot/1.0 (+https://github.com/noahwelter/MadFerry; once daily)"

SCHEDULE_PAGE_ID = 2909
WINDSLED_PAGE_ID = 4987
ALERTS_PAGE_ID = 570
SITE = "https://madferry.com"

TERMINALS = [
    {
        "id": "bayfield",
        "name": "Bayfield Terminal",
        "address": "20 Washington Ave, Bayfield, WI 54814",
        "latitude": 46.81191,
        "longitude": -90.81417,
    },
    {
        "id": "lapointe",
        "name": "La Pointe Terminal",
        "address": "Colonel Woods Ave, La Pointe, WI 54850",
        "latitude": 46.77923,
        "longitude": -90.78947,
    },
]
CROSSING_MINUTES = 25
