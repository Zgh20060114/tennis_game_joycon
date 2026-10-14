## Official tennis court dimensions (metres) plus ball and net parameters.
## Coordinate convention: Y up, net plane at Z = 0, player side Z > 0,
## opponent side Z < 0. X spans the court width.
const COURT_LENGTH := 23.77                 # baseline to baseline
const HALF_LENGTH := 11.885                 # baseline distance from the net
const SINGLES_WIDTH := 8.23
const SINGLES_HALF_WIDTH := 4.115
const DOUBLES_WIDTH := 10.97
const SERVICE_LINE_FROM_NET := 6.40
const NET_CENTER_HEIGHT := 0.914
const NET_POST_HEIGHT := 1.07
const NET_POST_OFFSET := 0.914              # posts sit this far outside the doubles sideline
const NET_HALF_SPAN := 6.399                # DOUBLES_WIDTH / 2 + NET_POST_OFFSET
const BALL_RADIUS := 0.033
const BALL_MASS := 0.057
const GRAVITY := 9.81
const BOUNCE_RESTITUTION := 0.73            # hard-court typical
const BOUNCE_FRICTION := 0.70               # horizontal velocity retention on bounce


## Net tape height above ground at lateral position x (parabolic sag
## between the two posts, lowest at the center strap).
static func net_height_at(x: float) -> float:
	var t: float = clampf(absf(x) / NET_HALF_SPAN, 0.0, 1.0)
	return NET_CENTER_HEIGHT + (NET_POST_HEIGHT - NET_CENTER_HEIGHT) * t * t


## True when (x, z) is inside the singles court on the given side
## (side = +1 for Z > 0 half, -1 for Z < 0 half).
static func in_singles_court(x: float, z: float, side: int) -> bool:
	return absf(x) <= SINGLES_HALF_WIDTH and side * z > 0.0 and absf(z) <= HALF_LENGTH
