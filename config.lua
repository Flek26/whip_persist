Config = {}

-- Street cars (GTA's own cars, not anyone's owned car) that a player has driven stay where they are left, and come
-- back if they are removed from the world. For this server session only: a restart forgets them. Owned cars are
-- whip_core's (kept, and rebuilt after a restart, already).

-- Models never kept (props attached as vehicles, trailers you don't want lying about...).
Config.Blacklist = {
    'rtxbumper',
}

-- At most this many kept at once. Over it, the one driven longest ago is let go (GTA may then clean it up).
Config.Max = 150

-- Let a car go after this many minutes nobody has driven it (0: never, for the session).
Config.ForgetAfterMinutes = 180

-- A kept car removed while a player stands this close (metres) was removed on purpose (/dv, a script someone used
-- next to it): it is forgotten, not brought back. 0: always bring it back.
Config.DeliberateRange = 8.0

-- How often (seconds) where each kept car stands is noted, for bringing it back where it was.
Config.SweepSeconds = 30

-- Say in the server console when a car is brought back.
Config.Debug = false
