#!/usr/bin/env python3
"""Source of truth for PRIME's bundled exercise library.

Run:  python3 tools/catalogue.py PRIME/Resources/exercises.json
It validates every entry (muscles, equipment, alternatives, thresholds) before writing.
Bump VERSION whenever entries change so existing installs pick up the new text.

Ranking thresholds are PRIME's own *provisional* starting points. Each entry gives four anchors
(Bronze, Silver, Gold, Elite); they're expanded to the seven thresholds of the v2 ladder
(Bronze, Silver, Gold, Platinum, Diamond, Elite, Master) with the same rule the app uses to
upgrade custom thresholds, so the original anchors keep their meaning.
"load" = estimated 1RM / bodyweight, "reps" = reps in a set.

Structured guides (overview, setup, mistakes with why/fix, safety, variations) live in
tools/guides.py together with the exercises added in v2.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import guides  # noqa: E402

VERSION = 2
MUSCLES = {"chest", "back", "traps", "shoulders", "biceps", "triceps", "forearms", "quadriceps",
           "hamstrings", "glutes", "adductors", "abductors", "calves", "abdominals", "lowerBack"}
EQUIPMENT = {"barbell", "dumbbell", "cable", "machine", "bodyweight", "band"}

BAR = "Total weight including the bar."
PER_DB = "Weight of one dumbbell."
ONE_DB = "Weight of the single dumbbell."
MACHINE = "Machine and cable loads differ between manufacturers, so compare these tiers only on similar equipment."
BW = "Reps in one set. Weighted sets are converted to bodyweight-equivalent reps."
BAND = "Band tension varies too much to rank fairly."
TIMED = "Holds and carries are tracked by time and aren't ranked."
LIGHT = "Light accessory work; tracked but not ranked."
ROTATION = "Rotational and anti-rotation work can't be measured consistently enough to rank."
NOTES = {"BAR": BAR, "PER_DB": PER_DB, "ONE_DB": ONE_DB, "MACHINE": MACHINE, "BW": BW,
         "TIMED": TIMED, "LIGHT": LIGHT, "ROTATION": ROTATION, "BAND": BAND}

E = []


def ex(slug, name, primary, secondary, equipment, mechanic, difficulty, instructions, tips, mistakes, alternatives, ranking):
    method, thresholds, note = ranking
    E.append({
        "slug": slug, "name": name, "primary": primary, "secondary": secondary,
        "equipment": equipment, "mechanic": mechanic, "difficulty": difficulty,
        "instructions": instructions, "tips": tips, "mistakes": mistakes, "alternatives": alternatives,
        "ranking": {"method": method, "thresholds": thresholds, "note": note},
    })


def load(t, note): return ("load", t, note)
def reps(t): return ("reps", t, BW)
NONE = ("none", [], BAND)

# ============================================================ CHEST
ex("barbell-bench-press", "Barbell Bench Press", ["chest"], ["triceps", "shoulders"], "barbell", "compound", "intermediate",
   ["Lie on the bench with your eyes under the bar and feet flat on the floor.",
    "Grip the bar slightly wider than shoulder width and squeeze your shoulder blades together.",
    "Unrack and lower the bar under control to your lower chest.",
    "Press up and slightly back until your arms are straight over your shoulders."],
   ["Keep a slight arch and your glutes on the bench.", "Tuck your elbows to about 45–70° from your body.", "Use a spotter or safety arms for heavy sets."],
   ["Bouncing the bar off the chest.", "Flaring the elbows straight out to the sides.", "Lifting the hips off the bench."],
   ["dumbbell-bench-press", "machine-chest-press", "push-up", "incline-barbell-bench-press"], load([0.6, 1.0, 1.35, 1.75], BAR))
ex("incline-barbell-bench-press", "Incline Barbell Bench Press", ["chest"], ["shoulders", "triceps"], "barbell", "compound", "intermediate",
   ["Set the bench to 30–45° and lie back with the bar over your eyes.",
    "Grip just wider than shoulder width with your shoulder blades pinned back.",
    "Lower the bar to your upper chest just below the collarbones.",
    "Press up until your arms lock out over your shoulders."],
   ["A lower incline keeps more of the work on the chest.", "Keep your wrists stacked over your elbows."],
   ["Setting the bench so steep it becomes a shoulder press.", "Letting the bar drift toward the face."],
   ["incline-dumbbell-press", "barbell-bench-press", "machine-chest-press"], load([0.5, 0.85, 1.15, 1.5], BAR))
ex("dumbbell-bench-press", "Dumbbell Bench Press", ["chest"], ["triceps", "shoulders"], "dumbbell", "compound", "beginner",
   ["Sit with the dumbbells on your thighs, then lie back and bring them to chest level.",
    "Start with the dumbbells just outside your chest, palms facing forward.",
    "Press up until your arms are straight, bringing the dumbbells slightly together.",
    "Lower slowly until you feel a stretch across the chest."],
   ["Dumbbells allow a deeper stretch than a bar.", "Kick the dumbbells up from your knees to get into position safely."],
   ["Dropping the dumbbells down too fast.", "Clanging them together at the top."],
   ["barbell-bench-press", "machine-chest-press", "incline-dumbbell-press"], load([0.25, 0.4, 0.55, 0.7], PER_DB))
ex("incline-dumbbell-press", "Incline Dumbbell Press", ["chest"], ["shoulders", "triceps"], "dumbbell", "compound", "beginner",
   ["Set the bench to 30–45° and sit back with the dumbbells at shoulder level.",
    "Press the dumbbells up over your upper chest.",
    "Lower them under control until your elbows are just below the bench line."],
   ["Keep your shoulder blades back and down throughout.", "Turn your palms slightly in if your shoulders feel pinched."],
   ["Arching so much that it becomes a flat press.", "Cutting the range of motion short."],
   ["incline-barbell-bench-press", "dumbbell-bench-press", "low-to-high-cable-fly"], load([0.2, 0.35, 0.5, 0.62], PER_DB))
ex("dumbbell-fly", "Dumbbell Fly", ["chest"], ["shoulders"], "dumbbell", "isolation", "beginner",
   ["Lie on a flat bench holding dumbbells above your chest, palms facing each other.",
    "With a slight bend in your elbows, open your arms out in a wide arc.",
    "Stop when you feel a strong stretch across your chest.",
    "Squeeze your chest to bring the dumbbells back up the same arc."],
   ["Think of hugging a large tree.", "Keep the elbow bend fixed throughout."],
   ["Turning it into a press by bending the elbows more.", "Going too heavy and overstretching the shoulders."],
   ["cable-fly", "pec-deck", "low-to-high-cable-fly"], load([0.08, 0.15, 0.22, 0.3], PER_DB))
ex("cable-fly", "Cable Fly", ["chest"], ["shoulders"], "cable", "isolation", "beginner",
   ["Set both pulleys at shoulder height and take a handle in each hand.",
    "Step forward into a staggered stance with a slight lean.",
    "Bring the handles together in front of your chest in a wide arc.",
    "Return slowly until your hands are in line with your chest."],
   ["Cables keep tension on the chest at the top where dumbbells don't.", "Pause and squeeze when the handles meet."],
   ["Bending and straightening the elbows.", "Letting the weight yank your arms back."],
   ["dumbbell-fly", "pec-deck", "low-to-high-cable-fly"], load([0.1, 0.18, 0.26, 0.34], MACHINE))
ex("low-to-high-cable-fly", "Low-to-High Cable Fly", ["chest"], ["shoulders"], "cable", "isolation", "beginner",
   ["Set both pulleys at the lowest position and grab a handle in each hand.",
    "With arms slightly bent, sweep the handles up and together to upper-chest height.",
    "Lower them back along the same path under control."],
   ["Targets the upper chest fibres.", "Keep your chest proud and shoulders down."],
   ["Shrugging the shoulders up.", "Using momentum from the legs."],
   ["cable-fly", "incline-dumbbell-press"], load([0.08, 0.15, 0.22, 0.3], MACHINE))
ex("pec-deck", "Pec Deck", ["chest"], ["shoulders"], "machine", "isolation", "beginner",
   ["Adjust the seat so the handles are at chest height.",
    "Sit tall with your back against the pad and grip the handles.",
    "Bring the handles together in front of you by squeezing your chest.",
    "Return slowly until you feel a stretch."],
   ["Keep a soft bend in the elbows.", "Pause for a second at full contraction."],
   ["Letting the shoulders roll forward.", "Letting the weight stack crash between reps."],
   ["cable-fly", "dumbbell-fly"], load([0.3, 0.55, 0.8, 1.05], MACHINE))
ex("machine-chest-press", "Machine Chest Press", ["chest"], ["triceps", "shoulders"], "machine", "compound", "beginner",
   ["Set the seat so the handles line up with your mid-chest.",
    "Press the handles forward until your arms are almost straight.",
    "Return slowly until your hands are just in front of your chest."],
   ["A great way to train the press safely to failure.", "Keep your shoulder blades against the pad."],
   ["Seat set too high or low.", "Letting the elbows flare up to shoulder height."],
   ["barbell-bench-press", "dumbbell-bench-press", "push-up"], load([0.5, 0.85, 1.15, 1.5], MACHINE))
ex("push-up", "Push-Up", ["chest"], ["triceps", "shoulders", "abdominals"], "bodyweight", "compound", "beginner",
   ["Start in a high plank with hands just wider than your shoulders.",
    "Brace your core so your body forms a straight line.",
    "Lower until your chest is just above the floor.",
    "Push back up to straight arms."],
   ["Elevate your hands on a bench to make it easier.", "Squeeze your glutes to stop your hips sagging."],
   ["Sagging hips.", "Half reps that stop well short of the floor."],
   ["diamond-push-up", "dumbbell-bench-press", "machine-chest-press"], reps([10, 25, 40, 60]))
ex("chest-dip", "Chest Dip", ["chest"], ["triceps", "shoulders"], "bodyweight", "compound", "intermediate",
   ["Support yourself on parallel bars with straight arms.",
    "Lean your torso forward and lower until your shoulders are just below your elbows.",
    "Press back up to straight arms."],
   ["The forward lean shifts work onto the chest.", "Add weight with a belt once 15 reps feels easy."],
   ["Dropping too deep with no control.", "Shrugging the shoulders up to the ears."],
   ["machine-dip", "dumbbell-bench-press", "push-up"], reps([5, 12, 20, 30]))
ex("band-chest-press", "Band Chest Press", ["chest"], ["triceps", "shoulders"], "band", "compound", "beginner",
   ["Anchor a band behind you at chest height and hold an end in each hand.",
    "Step forward to create tension and press your hands straight out.",
    "Return slowly to chest level."],
   ["Great for home or warm-ups.", "Use a staggered stance for balance."],
   ["Letting the band snap back.", "Arching the lower back."],
   ["push-up", "dumbbell-bench-press"], NONE)

# ============================================================ BACK
ex("pull-up", "Pull-Up", ["back"], ["biceps", "forearms"], "bodyweight", "compound", "intermediate",
   ["Hang from the bar with an overhand grip just wider than your shoulders.",
    "Pull your shoulder blades down, then drive your elbows toward your ribs.",
    "Pull until your chin clears the bar.",
    "Lower all the way to straight arms."],
   ["Use a band or the assisted machine to build up reps.", "Think about pulling the bar to your chest."],
   ["Kipping or swinging for momentum.", "Not lowering to a full hang."],
   ["chin-up", "lat-pulldown", "inverted-row"], reps([3, 8, 14, 20]))
ex("chin-up", "Chin-Up", ["back", "biceps"], ["forearms"], "bodyweight", "compound", "intermediate",
   ["Hang from the bar with palms facing you, hands shoulder-width apart.",
    "Pull your chest toward the bar, leading with your elbows.",
    "Lower slowly to a full hang."],
   ["The underhand grip brings the biceps in more.", "Keep your legs still."],
   ["Half reps.", "Craning the neck to get the chin over."],
   ["pull-up", "lat-pulldown"], reps([4, 9, 15, 21]))
ex("lat-pulldown", "Lat Pulldown", ["back"], ["biceps", "forearms"], "cable", "compound", "beginner",
   ["Sit with your thighs under the pads and grab the bar just wider than shoulder width.",
    "Lean back slightly and pull the bar to your upper chest.",
    "Squeeze your shoulder blades down and back at the bottom.",
    "Let the bar rise slowly until your arms are straight."],
   ["Drive the elbows down, not back.", "Use it to build toward bodyweight pull-ups."],
   ["Leaning way back to turn it into a row.", "Pulling the bar behind the neck."],
   ["pull-up", "straight-arm-pulldown", "seated-cable-row"], load([0.5, 0.8, 1.05, 1.3], MACHINE))
ex("barbell-bent-over-row", "Barbell Bent-Over Row", ["back"], ["biceps", "lowerBack", "forearms"], "barbell", "compound", "intermediate",
   ["Hold the bar with a shoulder-width overhand grip.",
    "Hinge at the hips until your torso is about 45° or lower, knees soft.",
    "Row the bar to your lower ribs, squeezing your shoulder blades.",
    "Lower it under control to straight arms."],
   ["Keep your back flat and neck neutral.", "Brace hard before each rep."],
   ["Standing more upright with every rep.", "Jerking the weight up with the hips."],
   ["dumbbell-row", "seated-cable-row", "machine-seated-row"], load([0.5, 0.8, 1.1, 1.4], BAR))
ex("dumbbell-row", "One-Arm Dumbbell Row", ["back"], ["biceps", "forearms"], "dumbbell", "compound", "beginner",
   ["Place one knee and hand on a bench, other foot on the floor.",
    "Hold a dumbbell with your free arm hanging straight down.",
    "Row the dumbbell toward your hip, keeping the elbow close.",
    "Lower it until your arm is straight."],
   ["Keep your shoulders level.", "Pull toward the hip to bias the lats."],
   ["Rotating the torso to heave the weight up.", "Shrugging instead of rowing."],
   ["barbell-bent-over-row", "seated-cable-row"], load([0.25, 0.4, 0.55, 0.75], PER_DB))
ex("seated-cable-row", "Seated Cable Row", ["back"], ["biceps", "forearms"], "cable", "compound", "beginner",
   ["Sit with feet on the platform and knees slightly bent, holding the handle.",
    "Sit tall and row the handle to your stomach.",
    "Squeeze your shoulder blades together.",
    "Extend your arms slowly to return."],
   ["Lead with the elbows.", "Keep your torso still."],
   ["Rocking back and forth.", "Rounding forward at the end of each rep."],
   ["machine-seated-row", "dumbbell-row", "barbell-bent-over-row"], load([0.5, 0.8, 1.1, 1.4], MACHINE))
ex("machine-seated-row", "Machine Seated Row", ["back"], ["biceps"], "machine", "compound", "beginner",
   ["Set the chest pad so you can just reach the handles with straight arms.",
    "Row the handles toward your torso.",
    "Pause and squeeze, then return slowly."],
   ["Chest-supported rows remove lower-back fatigue.", "Try different handles to change the grip."],
   ["Lifting the chest off the pad.", "Using a short, jerky range."],
   ["seated-cable-row", "dumbbell-row"], load([0.5, 0.8, 1.1, 1.4], MACHINE))
ex("straight-arm-pulldown", "Straight-Arm Pulldown", ["back"], ["triceps"], "cable", "isolation", "beginner",
   ["Stand facing a high pulley holding a straight bar or rope.",
    "With arms nearly straight, sweep the bar down to your thighs.",
    "Raise it slowly back to eye level."],
   ["A good way to feel the lats working.", "Hinge forward slightly."],
   ["Bending the elbows to make it a pushdown.", "Using the torso to swing the weight."],
   ["lat-pulldown", "dumbbell-pullover"], load([0.15, 0.27, 0.4, 0.52], MACHINE))
ex("dumbbell-pullover", "Dumbbell Pullover", ["back", "chest"], ["triceps"], "dumbbell", "isolation", "intermediate",
   ["Lie across or along a bench holding one dumbbell over your chest with both hands.",
    "Lower it back over your head with slightly bent elbows.",
    "Stop at a comfortable stretch and pull it back over your chest."],
   ["Keep the ribs down.", "Move only at the shoulders."],
   ["Going too heavy for the shoulder stretch.", "Bending the elbows a lot."],
   ["straight-arm-pulldown", "lat-pulldown"], load([0.15, 0.27, 0.38, 0.5], ONE_DB))
ex("inverted-row", "Inverted Row", ["back"], ["biceps", "abdominals"], "bodyweight", "compound", "beginner",
   ["Set a bar at waist height and hang underneath it with straight arms.",
    "Keep your body straight from head to heels.",
    "Pull your chest to the bar.",
    "Lower under control."],
   ["Bend your knees to make it easier.", "A great step toward pull-ups."],
   ["Letting the hips sag.", "Reaching the chin instead of the chest to the bar."],
   ["barbell-bent-over-row", "pull-up"], reps([6, 12, 20, 28]))
ex("face-pull", "Face Pull", ["shoulders"], ["back"], "cable", "isolation", "beginner",
   ["Set a rope at upper-chest height or higher.",
    "Pull the rope toward your face, splitting the ends apart.",
    "Finish with hands beside your ears and elbows high.",
    "Return slowly."],
   ["Great for shoulder health and posture.", "Think about pulling the rope apart."],
   ["Going too heavy and leaning back.", "Letting the elbows drop."],
   ["reverse-pec-deck", "band-pull-apart", "dumbbell-rear-delt-fly"], load([0.15, 0.25, 0.35, 0.45], MACHINE))
ex("barbell-shrug", "Barbell Shrug", ["back"], ["forearms"], "barbell", "isolation", "beginner",
   ["Hold a barbell at arm's length in front of your thighs.",
    "Lift your shoulders straight up toward your ears.",
    "Pause, then lower slowly."],
   ["Use straps if grip limits you.", "Think 'up', not round and round."],
   ["Rolling the shoulders.", "Bending the elbows."],
   ["dumbbell-shrug"], load([0.75, 1.25, 1.75, 2.25], BAR))
ex("dumbbell-shrug", "Dumbbell Shrug", ["back"], ["forearms"], "dumbbell", "isolation", "beginner",
   ["Hold dumbbells at your sides.", "Shrug your shoulders straight up.", "Pause and lower slowly."],
   ["Dumbbells let your arms hang naturally.", "Hold the top for a second."],
   ["Rolling the shoulders.", "Using a bouncing motion."],
   ["barbell-shrug"], load([0.25, 0.4, 0.55, 0.7], PER_DB))
ex("band-row", "Band Row", ["back"], ["biceps"], "band", "compound", "beginner",
   ["Anchor a band at chest height and hold the ends.", "Step back until there's tension.", "Row your hands to your ribs and return slowly."],
   ["Great for travel or warm-ups."], ["Leaning back instead of rowing."], ["seated-cable-row", "dumbbell-row"], NONE)
ex("band-pull-apart", "Band Pull-Apart", ["shoulders"], ["back"], "band", "isolation", "beginner",
   ["Hold a light band in front of you at shoulder height with straight arms.",
    "Pull the band apart until it touches your chest.",
    "Return slowly."],
   ["Perfect between sets or as a warm-up.", "Keep the shoulders down."],
   ["Shrugging up.", "Bending the elbows a lot."],
   ["face-pull", "reverse-pec-deck"], NONE)

# ============================================================ LOWER BACK / POSTERIOR CHAIN
ex("conventional-deadlift", "Deadlift", ["hamstrings", "glutes", "lowerBack"], ["back", "forearms", "quadriceps"], "barbell", "compound", "advanced",
   ["Stand with the bar over your mid-foot, feet hip-width apart.",
    "Hinge down and grip the bar just outside your legs.",
    "Flatten your back, pull the slack out of the bar and brace.",
    "Push the floor away and stand up tall, keeping the bar close.",
    "Lower it by hinging at the hips, then bending the knees."],
   ["The bar should travel in a straight vertical line.", "Brace like you're about to be punched."],
   ["Rounding the lower back.", "Jerking the bar off the floor.", "Leaning back at the top."],
   ["sumo-deadlift", "romanian-deadlift", "trap-bar-deadlift"], load([1.0, 1.5, 2.0, 2.5], BAR))
ex("sumo-deadlift", "Sumo Deadlift", ["glutes", "quadriceps", "hamstrings"], ["lowerBack", "back", "forearms"], "barbell", "compound", "advanced",
   ["Take a wide stance with toes turned out and the bar over mid-foot.",
    "Grip the bar inside your knees with straight arms.",
    "Push your knees out, lift your chest and brace.",
    "Drive through the floor to stand up, then lower under control."],
   ["Hips start closer to the bar than in a conventional pull.", "Push the knees out the whole way."],
   ["Knees caving in.", "Hips shooting up first."],
   ["conventional-deadlift", "trap-bar-deadlift"], load([1.0, 1.5, 2.0, 2.5], BAR))
ex("trap-bar-deadlift", "Trap Bar Deadlift", ["quadriceps", "glutes", "hamstrings"], ["lowerBack", "back", "forearms"], "barbell", "compound", "intermediate",
   ["Stand in the centre of the trap bar and grip the handles.",
    "Sit your hips down with a flat back and chest up.",
    "Drive through your legs to stand tall.",
    "Lower by bending hips and knees together."],
   ["Easier on the lower back than a straight bar.", "Great for learning to pull heavy."],
   ["Rounding the back.", "Letting the hips rise first."],
   ["conventional-deadlift", "leg-press"], load([1.0, 1.6, 2.2, 2.75], BAR))
ex("romanian-deadlift", "Romanian Deadlift", ["hamstrings"], ["glutes", "lowerBack", "forearms"], "barbell", "compound", "intermediate",
   ["Hold the bar at hip height with an overhand grip.",
    "Soften the knees and push your hips back, sliding the bar down your thighs.",
    "Stop when you feel a strong hamstring stretch, usually just below the knees.",
    "Drive the hips forward to stand back up."],
   ["Keep the bar in contact with your legs.", "The movement is a hinge, not a squat."],
   ["Rounding the back to reach lower.", "Bending the knees too much."],
   ["dumbbell-romanian-deadlift", "lying-leg-curl", "good-morning"], load([0.75, 1.1, 1.5, 1.9], BAR))
ex("dumbbell-romanian-deadlift", "Dumbbell Romanian Deadlift", ["hamstrings"], ["glutes", "lowerBack"], "dumbbell", "compound", "beginner",
   ["Hold dumbbells in front of your thighs.",
    "Push your hips back and lower the dumbbells along your legs.",
    "Stop at a strong hamstring stretch, then stand back up."],
   ["Keep the dumbbells close.", "Squeeze the glutes at the top."],
   ["Rounding the back.", "Turning it into a squat."],
   ["romanian-deadlift", "seated-leg-curl"], load([0.25, 0.4, 0.55, 0.7], PER_DB))
ex("good-morning", "Good Morning", ["hamstrings", "lowerBack"], ["glutes"], "barbell", "compound", "advanced",
   ["Set a bar across your upper back as for a squat.",
    "With soft knees, push your hips back and lower your torso.",
    "Stop just above parallel and return to standing."],
   ["Start light; it's a strong lever on the lower back.", "Keep the back flat throughout."],
   ["Going too heavy too soon.", "Rounding the spine."],
   ["romanian-deadlift", "back-extension"], load([0.4, 0.65, 0.9, 1.15], BAR))
ex("back-extension", "Back Extension", ["lowerBack"], ["glutes", "hamstrings"], "bodyweight", "isolation", "beginner",
   ["Set the pad just below your hips on a 45° or horizontal bench.",
    "Cross your arms and lower your torso by hinging at the hips.",
    "Raise back up until your body is in a straight line."],
   ["Hold a plate to your chest to add load.", "Don't hyperextend at the top."],
   ["Swinging up fast.", "Overarching past straight."],
   ["good-morning", "romanian-deadlift"], reps([10, 20, 30, 40]))
ex("cable-pull-through", "Cable Pull-Through", ["glutes"], ["hamstrings", "lowerBack"], "cable", "compound", "beginner",
   ["Face away from a low pulley with a rope between your legs.",
    "Hinge your hips back and let the rope pass between your legs.",
    "Drive your hips forward to stand tall, squeezing your glutes."],
   ["A friendly way to learn the hip hinge.", "Arms just hold the rope; the hips do the work."],
   ["Squatting down instead of hinging.", "Pulling with the arms."],
   ["barbell-hip-thrust", "romanian-deadlift"], load([0.3, 0.5, 0.75, 1.0], MACHINE))

# ============================================================ SHOULDERS
ex("overhead-press", "Overhead Press", ["shoulders"], ["triceps", "abdominals"], "barbell", "compound", "intermediate",
   ["Stand with the bar on your front shoulders, hands just outside shoulder width.",
    "Brace your core and squeeze your glutes.",
    "Press the bar straight up, moving your head back slightly to let it pass.",
    "Lock out overhead with the bar over your mid-foot, then lower."],
   ["Push your head 'through the window' at the top.", "Keep your ribs down."],
   ["Leaning back into a standing incline press.", "Pressing the bar forward instead of up."],
   ["dumbbell-shoulder-press", "machine-shoulder-press", "pike-push-up"], load([0.4, 0.6, 0.8, 1.05], BAR))
ex("dumbbell-shoulder-press", "Dumbbell Shoulder Press", ["shoulders"], ["triceps"], "dumbbell", "compound", "beginner",
   ["Sit on an upright bench with dumbbells at shoulder height, palms forward.",
    "Press them overhead until your arms are straight.",
    "Lower them back to shoulder height."],
   ["Keep your back against the pad.", "Don't let the dumbbells drift too far forward."],
   ["Arching the lower back.", "Cutting the depth short."],
   ["overhead-press", "machine-shoulder-press", "arnold-press"], load([0.15, 0.27, 0.38, 0.5], PER_DB))
ex("arnold-press", "Arnold Press", ["shoulders"], ["triceps"], "dumbbell", "compound", "intermediate",
   ["Start with dumbbells in front of your shoulders, palms facing you.",
    "Press up while rotating your palms to face forward.",
    "Reverse the rotation as you lower."],
   ["The rotation works the front of the shoulder through a longer path.", "Use a lighter weight than a normal press."],
   ["Rushing the rotation.", "Arching the back."],
   ["dumbbell-shoulder-press", "machine-shoulder-press"], load([0.13, 0.24, 0.34, 0.45], PER_DB))
ex("machine-shoulder-press", "Machine Shoulder Press", ["shoulders"], ["triceps"], "machine", "compound", "beginner",
   ["Set the seat so the handles start at shoulder height.",
    "Press the handles up until your arms are straight.",
    "Lower under control."],
   ["Safe to push close to failure.", "Keep your head against the pad."],
   ["Seat too low, which jams the shoulders.", "Bouncing the weight stack."],
   ["dumbbell-shoulder-press", "overhead-press"], load([0.35, 0.6, 0.85, 1.1], MACHINE))
ex("dumbbell-lateral-raise", "Dumbbell Lateral Raise", ["shoulders"], [], "dumbbell", "isolation", "beginner",
   ["Stand holding light dumbbells at your sides.",
    "With a slight bend in the elbows, raise your arms out to the side.",
    "Stop at shoulder height, then lower slowly."],
   ["Lead with your elbows.", "Light weight and strict form win here."],
   ["Swinging the weight up.", "Shrugging the traps."],
   ["cable-lateral-raise", "machine-shoulder-press"], load([0.05, 0.1, 0.15, 0.2], PER_DB))
ex("cable-lateral-raise", "Cable Lateral Raise", ["shoulders"], [], "cable", "isolation", "beginner",
   ["Stand side-on to a low pulley, holding the handle in your far hand.",
    "Raise your arm out to the side to shoulder height.",
    "Lower slowly to the start."],
   ["The cable keeps tension at the bottom.", "Lean away slightly for a longer range."],
   ["Turning the torso.", "Using momentum."],
   ["dumbbell-lateral-raise"], load([0.04, 0.08, 0.12, 0.16], MACHINE))
ex("dumbbell-front-raise", "Dumbbell Front Raise", ["shoulders"], ["chest"], "dumbbell", "isolation", "beginner",
   ["Hold dumbbells in front of your thighs.", "Raise them straight in front of you to shoulder height.", "Lower slowly."],
   ["Alternate arms if you like.", "Keep your torso still."],
   ["Leaning back.", "Swinging the weights."],
   ["overhead-press", "dumbbell-lateral-raise"], load([0.06, 0.11, 0.16, 0.21], PER_DB))
ex("dumbbell-rear-delt-fly", "Dumbbell Rear Delt Fly", ["shoulders"], ["back"], "dumbbell", "isolation", "beginner",
   ["Hinge forward with a flat back, dumbbells hanging below your chest.",
    "Raise your arms out to the sides with slightly bent elbows.",
    "Squeeze at the top and lower slowly."],
   ["Use light weights.", "Lead with the back of your hands."],
   ["Using the traps to shrug the weight up.", "Standing up as you lift."],
   ["reverse-pec-deck", "face-pull", "band-pull-apart"], load([0.04, 0.08, 0.12, 0.17], PER_DB))
ex("reverse-pec-deck", "Reverse Pec Deck", ["shoulders"], ["back"], "machine", "isolation", "beginner",
   ["Sit facing the pec deck pad with the handles set behind.",
    "Grip the handles with straight arms at shoulder height.",
    "Sweep your arms back until they're in line with your body.",
    "Return slowly."],
   ["A steady way to train the rear shoulders.", "Keep your chest on the pad."],
   ["Bending the elbows.", "Going too heavy."],
   ["dumbbell-rear-delt-fly", "face-pull"], load([0.2, 0.35, 0.5, 0.65], MACHINE))
ex("pike-push-up", "Pike Push-Up", ["shoulders"], ["triceps"], "bodyweight", "compound", "intermediate",
   ["Start in a push-up position, then walk your feet in so your hips are high.",
    "Bend your elbows to lower your head toward the floor in front of your hands.",
    "Press back up."],
   ["Elevate your feet to make it harder.", "A good step toward handstand push-ups."],
   ["Letting the hips drop.", "Flaring the elbows out wide."],
   ["overhead-press", "dumbbell-shoulder-press"], reps([5, 12, 20, 30]))
ex("band-lateral-raise", "Band Lateral Raise", ["shoulders"], [], "band", "isolation", "beginner",
   ["Stand on a band holding an end in each hand.", "Raise your arms out to shoulder height.", "Lower slowly."],
   ["Tension rises toward the top."], ["Shrugging."], ["dumbbell-lateral-raise", "cable-lateral-raise"], NONE)

# ============================================================ BICEPS
ex("barbell-curl", "Barbell Curl", ["biceps"], ["forearms"], "barbell", "isolation", "beginner",
   ["Stand holding a barbell with an underhand, shoulder-width grip.",
    "Keep your elbows at your sides and curl the bar toward your shoulders.",
    "Squeeze, then lower slowly to straight arms."],
   ["An EZ bar is kinder on the wrists.", "Control the lowering phase."],
   ["Swinging the hips to lift the bar.", "Letting the elbows drift forward."],
   ["dumbbell-bicep-curl", "cable-curl", "machine-preacher-curl"], load([0.25, 0.4, 0.55, 0.7], BAR))
ex("dumbbell-bicep-curl", "Dumbbell Bicep Curl", ["biceps"], ["forearms"], "dumbbell", "isolation", "beginner",
   ["Stand holding dumbbells at your sides, palms forward.",
    "Curl them up while keeping your elbows pinned.",
    "Lower slowly until your arms are straight."],
   ["Turn your little finger up at the top for a stronger squeeze.", "Alternate arms if you like."],
   ["Swinging the weights.", "Half reps."],
   ["barbell-curl", "hammer-curl", "cable-curl"], load([0.1, 0.18, 0.27, 0.36], PER_DB))
ex("hammer-curl", "Hammer Curl", ["biceps", "forearms"], [], "dumbbell", "isolation", "beginner",
   ["Hold dumbbells at your sides with palms facing in.",
    "Curl them up keeping your palms facing each other.",
    "Lower under control."],
   ["Builds the brachialis and forearms.", "Keep the wrists neutral."],
   ["Swinging.", "Moving the elbows forward."],
   ["dumbbell-bicep-curl", "reverse-curl"], load([0.11, 0.2, 0.29, 0.38], PER_DB))
ex("concentration-curl", "Concentration Curl", ["biceps"], [], "dumbbell", "isolation", "beginner",
   ["Sit with your elbow braced against your inner thigh.", "Curl the dumbbell toward your shoulder.", "Lower slowly."],
   ["No cheating possible, so go lighter.", "Squeeze hard at the top."],
   ["Lifting the elbow off the thigh.", "Rushing the lowering."],
   ["dumbbell-bicep-curl", "machine-preacher-curl"], load([0.08, 0.15, 0.22, 0.3], PER_DB))
ex("cable-curl", "Cable Curl", ["biceps"], ["forearms"], "cable", "isolation", "beginner",
   ["Stand facing a low pulley holding a straight bar or EZ attachment.",
    "Curl the bar up while keeping your elbows still.",
    "Lower slowly to straight arms."],
   ["Constant tension through the whole rep.", "Step back slightly for tension at the bottom."],
   ["Leaning back.", "Elbows drifting forward."],
   ["barbell-curl", "dumbbell-bicep-curl"], load([0.2, 0.32, 0.45, 0.58], MACHINE))
ex("machine-preacher-curl", "Machine Preacher Curl", ["biceps"], [], "machine", "isolation", "beginner",
   ["Adjust the seat so your upper arms rest flat on the pad.",
    "Curl the handles up toward your shoulders.",
    "Lower slowly to almost straight arms."],
   ["The pad stops you cheating.", "Don't lock out hard at the bottom."],
   ["Lifting the elbows off the pad.", "Dropping the weight."],
   ["concentration-curl", "barbell-curl"], load([0.2, 0.32, 0.45, 0.58], MACHINE))
ex("band-bicep-curl", "Band Bicep Curl", ["biceps"], ["forearms"], "band", "isolation", "beginner",
   ["Stand on a band holding an end in each hand.", "Curl your hands to your shoulders.", "Lower slowly."],
   ["Good for high-rep finishers."], ["Letting the band snap down."], ["dumbbell-bicep-curl", "cable-curl"], NONE)

# ============================================================ TRICEPS
ex("close-grip-bench-press", "Close-Grip Bench Press", ["triceps"], ["chest", "shoulders"], "barbell", "compound", "intermediate",
   ["Lie on a bench and grip the bar about shoulder-width apart.",
    "Lower the bar to your lower chest with elbows tucked.",
    "Press back up to lockout."],
   ["Shoulder-width is close enough; narrower strains the wrists.", "Keep elbows close to your sides."],
   ["Gripping too narrow.", "Flaring the elbows."],
   ["skull-crusher", "cable-triceps-pushdown", "diamond-push-up"], load([0.5, 0.85, 1.15, 1.45], BAR))
ex("skull-crusher", "Skull Crusher", ["triceps"], [], "barbell", "isolation", "intermediate",
   ["Lie on a bench holding an EZ bar over your chest with arms straight.",
    "Bend your elbows to lower the bar toward your forehead.",
    "Extend your arms to return."],
   ["Lower slightly behind the head for a bigger stretch.", "Keep the upper arms still."],
   ["Flaring the elbows.", "Moving the upper arms like a pullover."],
   ["overhead-dumbbell-extension", "cable-triceps-pushdown"], load([0.2, 0.35, 0.5, 0.65], BAR))
ex("cable-triceps-pushdown", "Cable Triceps Pushdown", ["triceps"], [], "cable", "isolation", "beginner",
   ["Stand facing a high pulley with a bar or rope.",
    "With elbows pinned at your sides, push the handle down until your arms are straight.",
    "Let it rise slowly until your forearms are just above parallel."],
   ["Spread a rope apart at the bottom for a stronger squeeze.", "Keep your shoulders down."],
   ["Leaning over the weight.", "Letting the elbows flare forward."],
   ["overhead-cable-triceps-extension", "skull-crusher", "machine-dip"], load([0.2, 0.35, 0.5, 0.65], MACHINE))
ex("overhead-cable-triceps-extension", "Overhead Cable Triceps Extension", ["triceps"], [], "cable", "isolation", "beginner",
   ["Face away from a pulley holding a rope behind your head.",
    "Stagger your stance and keep your elbows high.",
    "Extend your arms forward and up until straight.",
    "Return slowly to a deep stretch."],
   ["The overhead position stretches the long head of the triceps.", "Keep the elbows pointing forward."],
   ["Elbows flaring out wide.", "Arching the lower back."],
   ["overhead-dumbbell-extension", "cable-triceps-pushdown"], load([0.15, 0.27, 0.38, 0.5], MACHINE))
ex("overhead-dumbbell-extension", "Overhead Dumbbell Extension", ["triceps"], [], "dumbbell", "isolation", "beginner",
   ["Sit tall holding one dumbbell overhead with both hands.",
    "Lower it behind your head by bending your elbows.",
    "Extend back up to straight arms."],
   ["Keep your elbows close to your head.", "A bench with back support helps."],
   ["Flaring the elbows.", "Arching the back."],
   ["overhead-cable-triceps-extension", "skull-crusher"], load([0.12, 0.22, 0.32, 0.42], ONE_DB))
ex("dumbbell-kickback", "Dumbbell Kickback", ["triceps"], [], "dumbbell", "isolation", "beginner",
   ["Hinge forward with your upper arm parallel to the floor.",
    "Extend your elbow until your arm is straight behind you.",
    "Lower slowly."],
   ["Hold the top for a second.", "Very light weights work."],
   ["Swinging the arm.", "Dropping the elbow."],
   ["cable-triceps-pushdown"], load([0.05, 0.09, 0.14, 0.19], PER_DB))
ex("triceps-dip", "Triceps Dip", ["triceps"], ["chest", "shoulders"], "bodyweight", "compound", "intermediate",
   ["Support yourself on parallel bars with arms straight and body upright.",
    "Bend your elbows to lower until your upper arms are about parallel to the floor.",
    "Press back up to straight arms."],
   ["Stay upright to keep the triceps doing the work.", "Use the assisted machine to build up."],
   ["Leaning far forward.", "Bouncing at the bottom."],
   ["machine-dip", "close-grip-bench-press", "diamond-push-up"], reps([5, 12, 20, 30]))
ex("diamond-push-up", "Diamond Push-Up", ["triceps"], ["chest", "shoulders"], "bodyweight", "compound", "intermediate",
   ["Start in a push-up with your hands together under your chest, forming a diamond.",
    "Lower your chest toward your hands, elbows close.",
    "Push back up."],
   ["Drop to your knees to make it easier.", "Keep your body straight."],
   ["Flaring the elbows.", "Sagging hips."],
   ["push-up", "close-grip-bench-press"], reps([5, 15, 25, 40]))
ex("machine-dip", "Machine Dip", ["triceps"], ["chest"], "machine", "compound", "beginner",
   ["Sit with the handles beside your hips.",
    "Press the handles down until your arms are straight.",
    "Let them rise slowly."],
   ["Lets you load the dip safely.", "Keep your chest up."],
   ["Shrugging the shoulders.", "Partial reps."],
   ["triceps-dip", "cable-triceps-pushdown"], load([0.5, 0.85, 1.2, 1.55], MACHINE))
ex("band-triceps-pushdown", "Band Triceps Pushdown", ["triceps"], [], "band", "isolation", "beginner",
   ["Anchor a band overhead and hold an end in each hand.", "Push down until your arms are straight.", "Return slowly."],
   ["A handy home alternative."], ["Letting the elbows drift."], ["cable-triceps-pushdown"], NONE)

# ============================================================ FOREARMS
ex("dumbbell-wrist-curl", "Dumbbell Wrist Curl", ["forearms"], [], "dumbbell", "isolation", "beginner",
   ["Sit with your forearms on your thighs, palms up, wrists past your knees.",
    "Let the dumbbells roll down to your fingertips.",
    "Curl your wrists up as high as you can."],
   ["High reps work well.", "Keep the forearms flat on your legs."],
   ["Lifting the forearms.", "Using a tiny range."],
   ["reverse-curl", "hammer-curl"], load([0.08, 0.14, 0.2, 0.27], PER_DB))
ex("reverse-curl", "Reverse Curl", ["forearms"], ["biceps"], "barbell", "isolation", "beginner",
   ["Hold a barbell or EZ bar with an overhand grip.",
    "Curl it up keeping your wrists straight.",
    "Lower slowly."],
   ["Works the top of the forearm.", "Go lighter than a normal curl."],
   ["Letting the wrists bend.", "Swinging."],
   ["hammer-curl", "dumbbell-wrist-curl"], load([0.18, 0.3, 0.42, 0.55], BAR))

# ============================================================ QUADS
ex("barbell-back-squat", "Barbell Back Squat", ["quadriceps", "glutes"], ["hamstrings", "lowerBack", "abdominals"], "barbell", "compound", "intermediate",
   ["Set the bar on your upper back and step out with feet about shoulder-width apart.",
    "Brace your core and sit down between your heels.",
    "Go to at least thigh-parallel, keeping your chest up.",
    "Drive through the whole foot to stand back up."],
   ["Knees track over the toes.", "Take a big breath and brace before each rep."],
   ["Knees caving in.", "Heels lifting.", "Cutting depth short."],
   ["front-squat", "goblet-squat", "leg-press", "hack-squat"], load([0.75, 1.25, 1.75, 2.25], BAR))
ex("front-squat", "Front Squat", ["quadriceps"], ["glutes", "abdominals", "back"], "barbell", "compound", "advanced",
   ["Rest the bar on your front shoulders with elbows high.",
    "Sit straight down keeping your torso upright.",
    "Drive up keeping your elbows high."],
   ["Crossed arms work if wrist mobility is limited.", "Upright posture keeps the work on the quads."],
   ["Elbows dropping and the bar rolling forward.", "Rounding the upper back."],
   ["barbell-back-squat", "goblet-squat", "hack-squat"], load([0.6, 1.0, 1.4, 1.8], BAR))
ex("goblet-squat", "Goblet Squat", ["quadriceps", "glutes"], ["abdominals"], "dumbbell", "compound", "beginner",
   ["Hold one dumbbell vertically against your chest.",
    "Squat down between your knees, keeping your chest tall.",
    "Stand back up driving through your heels."],
   ["The best way to learn the squat.", "Elbows can gently push your knees out at the bottom."],
   ["Letting the dumbbell pull you forward.", "Heels lifting."],
   ["barbell-back-squat", "leg-press"], load([0.25, 0.45, 0.65, 0.85], ONE_DB))
ex("leg-press", "Leg Press", ["quadriceps", "glutes"], ["hamstrings"], "machine", "compound", "beginner",
   ["Sit with your back flat on the pad and feet shoulder-width on the platform.",
    "Release the safeties and lower the platform until your knees reach about 90°.",
    "Press back up without locking your knees hard."],
   ["Higher foot placement works the glutes more.", "Keep your lower back on the pad."],
   ["Lowering so far the hips curl off the seat.", "Locking out the knees."],
   ["barbell-back-squat", "hack-squat", "goblet-squat"], load([1.0, 1.75, 2.5, 3.25], MACHINE))
ex("hack-squat", "Hack Squat", ["quadriceps"], ["glutes"], "machine", "compound", "intermediate",
   ["Stand on the platform with your back against the pad and shoulders under the pads.",
    "Release the safeties and squat down to at least parallel.",
    "Drive back up through your feet."],
   ["A narrower stance hits the quads harder.", "Control the bottom."],
   ["Knees caving.", "Half reps."],
   ["leg-press", "barbell-back-squat", "smith-machine-squat"], load([0.75, 1.25, 1.75, 2.25], MACHINE))
ex("smith-machine-squat", "Smith Machine Squat", ["quadriceps", "glutes"], ["hamstrings"], "machine", "compound", "beginner",
   ["Set the bar on your upper back with feet slightly in front of you.",
    "Unhook the bar and squat down to parallel.",
    "Push back up and re-rack using the hooks."],
   ["The fixed path lets you focus on the legs.", "Set the safety stops just below your lowest point."],
   ["Feet directly under the bar, which strains the knees.", "Bouncing at the bottom."],
   ["barbell-back-squat", "hack-squat"], load([0.6, 1.0, 1.5, 1.9], MACHINE))
ex("leg-extension", "Leg Extension", ["quadriceps"], [], "machine", "isolation", "beginner",
   ["Sit with the pad on your lower shins and knees lined up with the machine's pivot.",
    "Straighten your legs fully.",
    "Lower slowly to about 90°."],
   ["Pause at the top for a strong squeeze.", "Point your toes up."],
   ["Swinging the weight up.", "Lifting the hips off the seat."],
   ["leg-press", "bulgarian-split-squat"], load([0.35, 0.6, 0.85, 1.1], MACHINE))
ex("bulgarian-split-squat", "Bulgarian Split Squat", ["quadriceps", "glutes"], ["hamstrings"], "dumbbell", "compound", "intermediate",
   ["Stand in front of a bench and rest the top of your back foot on it.",
    "Holding dumbbells, lower your back knee toward the floor.",
    "Push through your front foot to stand back up."],
   ["A slight forward lean works the glutes more.", "Find a stance where your front heel stays down."],
   ["Front foot too close to the bench.", "Pushing off the back foot."],
   ["dumbbell-walking-lunge", "goblet-squat"], load([0.12, 0.22, 0.32, 0.42], PER_DB))
ex("dumbbell-walking-lunge", "Dumbbell Walking Lunge", ["quadriceps", "glutes"], ["hamstrings", "calves"], "dumbbell", "compound", "beginner",
   ["Hold dumbbells at your sides and step forward into a lunge.",
    "Lower until your back knee nearly touches the floor.",
    "Drive through your front foot and step straight into the next lunge."],
   ["Count each leg as one rep, or log reps per leg consistently.", "Take long steps for more glute work."],
   ["Short steps that push the knee far past the toes.", "Leaning the torso way forward."],
   ["bulgarian-split-squat", "barbell-lunge"], load([0.12, 0.22, 0.32, 0.42], PER_DB))
ex("barbell-lunge", "Barbell Reverse Lunge", ["quadriceps", "glutes"], ["hamstrings"], "barbell", "compound", "intermediate",
   ["Set a bar on your upper back.", "Step back and lower your back knee toward the floor.", "Drive through the front foot to return."],
   ["Stepping back is easier on the knees.", "Keep your torso upright."],
   ["Narrow tightrope stance.", "Wobbling knees."],
   ["dumbbell-walking-lunge", "bulgarian-split-squat"], load([0.4, 0.7, 1.0, 1.3], BAR))
ex("bodyweight-squat", "Bodyweight Squat", ["quadriceps", "glutes"], [], "bodyweight", "compound", "beginner",
   ["Stand with feet shoulder-width apart, arms in front for balance.",
    "Sit down as low as you comfortably can with your chest up.",
    "Stand back up."],
   ["Great warm-up or home workout.", "Keep the whole foot planted."],
   ["Heels lifting.", "Knees collapsing inward."],
   ["goblet-squat", "pistol-squat"], reps([20, 40, 60, 80]))
ex("pistol-squat", "Pistol Squat", ["quadriceps", "glutes"], ["abdominals"], "bodyweight", "compound", "advanced",
   ["Stand on one leg with the other straight out in front.",
    "Squat down on the standing leg as low as you can.",
    "Stand back up without touching the free foot down."],
   ["Hold a post or sit to a box while learning.", "Count reps per leg."],
   ["Collapsing at the bottom.", "Heel lifting."],
   ["bulgarian-split-squat", "bodyweight-squat"], reps([1, 5, 10, 15]))
ex("band-squat", "Band Squat", ["quadriceps", "glutes"], [], "band", "compound", "beginner",
   ["Stand on a band and loop it over your shoulders.", "Squat down and stand back up against the band."],
   ["Hardest at the top where you're strongest."], ["Letting the band pull you forward."], ["goblet-squat", "bodyweight-squat"], NONE)

# ============================================================ HAMSTRINGS
ex("lying-leg-curl", "Lying Leg Curl", ["hamstrings"], ["calves"], "machine", "isolation", "beginner",
   ["Lie face down with the pad just above your heels and knees just off the bench.",
    "Curl your heels toward your glutes.",
    "Lower slowly to straight legs."],
   ["Keep your hips pressed into the pad.", "Control the way down."],
   ["Hips lifting off the pad.", "Jerking the weight."],
   ["seated-leg-curl", "romanian-deadlift", "nordic-curl"], load([0.25, 0.45, 0.65, 0.85], MACHINE))
ex("seated-leg-curl", "Seated Leg Curl", ["hamstrings"], ["calves"], "machine", "isolation", "beginner",
   ["Sit with the pad behind your lower calves and the thigh pad snug.",
    "Curl your heels down and back under the seat.",
    "Let them rise slowly."],
   ["Lean forward slightly for a bigger hamstring stretch.", "Pause at full contraction."],
   ["Loose thigh pad letting you lift up.", "Partial reps."],
   ["lying-leg-curl", "romanian-deadlift"], load([0.3, 0.5, 0.7, 0.9], MACHINE))
ex("nordic-curl", "Nordic Hamstring Curl", ["hamstrings"], ["glutes"], "bodyweight", "isolation", "advanced",
   ["Kneel with your ankles anchored under a pad or by a partner.",
    "Keeping your hips straight, lower your body forward as slowly as you can.",
    "Catch yourself with your hands and pull back up with your hamstrings."],
   ["Even slow lowering alone builds strength.", "Keep a straight line from knees to head."],
   ["Bending at the hips.", "Dropping fast."],
   ["lying-leg-curl", "seated-leg-curl"], reps([1, 3, 6, 10]))

# ============================================================ GLUTES
ex("barbell-hip-thrust", "Barbell Hip Thrust", ["glutes"], ["hamstrings"], "barbell", "compound", "intermediate",
   ["Sit with your upper back against a bench and a padded bar over your hips.",
    "Plant your feet so your shins are vertical at the top.",
    "Drive your hips up until your body is flat from shoulders to knees.",
    "Lower slowly."],
   ["Tuck your chin and keep ribs down.", "Pause and squeeze at the top."],
   ["Overarching the lower back.", "Feet too far out."],
   ["glute-bridge", "cable-pull-through"], load([1.0, 1.5, 2.0, 2.6], BAR))
ex("glute-bridge", "Glute Bridge", ["glutes"], ["hamstrings"], "bodyweight", "isolation", "beginner",
   ["Lie on your back with knees bent and feet flat.",
    "Drive your hips up until your body is straight from shoulders to knees.",
    "Lower slowly."],
   ["Push through your heels.", "Do single-leg reps to make it harder."],
   ["Arching the back.", "Feet too close."],
   ["barbell-hip-thrust", "cable-glute-kickback"], reps([15, 30, 45, 60]))
ex("cable-glute-kickback", "Cable Glute Kickback", ["glutes"], ["hamstrings"], "cable", "isolation", "beginner",
   ["Attach an ankle strap to a low pulley.",
    "Hold the frame and kick your leg straight back.",
    "Squeeze at the top and return slowly."],
   ["Keep your torso still.", "Small range, full squeeze."],
   ["Arching the lower back to kick higher.", "Swinging."],
   ["glute-bridge", "barbell-hip-thrust"], load([0.05, 0.1, 0.15, 0.2], MACHINE))
ex("hip-abduction-machine", "Hip Abduction Machine", ["glutes"], [], "machine", "isolation", "beginner",
   ["Sit with the pads against the outside of your knees.",
    "Push your knees out as far as you can.",
    "Return slowly."],
   ["Lean forward slightly to bias the upper glutes.", "Pause when fully open."],
   ["Letting the weights slam.", "Bouncing."],
   ["band-lateral-walk", "cable-glute-kickback"], load([0.4, 0.7, 1.0, 1.3], MACHINE))
ex("band-lateral-walk", "Band Lateral Walk", ["glutes"], [], "band", "isolation", "beginner",
   ["Place a loop band around your legs above the knees.", "Sit into a quarter squat.", "Step sideways, keeping tension on the band."],
   ["A great glute warm-up."], ["Standing up tall.", "Knees caving in."], ["hip-abduction-machine"], NONE)

# ============================================================ CALVES
ex("standing-calf-raise", "Standing Calf Raise", ["calves"], [], "machine", "isolation", "beginner",
   ["Stand on the step with the pads on your shoulders and heels hanging off.",
    "Lower your heels for a deep stretch.",
    "Rise up onto your toes as high as you can."],
   ["Pause at the bottom to kill the bounce.", "Straight knees work the upper calf."],
   ["Bouncing through short reps.", "Bending the knees to help."],
   ["seated-calf-raise", "single-leg-calf-raise"], load([0.75, 1.25, 1.75, 2.25], MACHINE))
ex("seated-calf-raise", "Seated Calf Raise", ["calves"], [], "machine", "isolation", "beginner",
   ["Sit with the pad on your lower thighs and balls of your feet on the step.",
    "Lower your heels for a full stretch.",
    "Raise them as high as you can."],
   ["Bent knees target the deeper soleus.", "Slow reps work best."],
   ["Short bouncing reps.", "Using your hands to push."],
   ["standing-calf-raise"], load([0.4, 0.75, 1.1, 1.5], MACHINE))
ex("single-leg-calf-raise", "Single-Leg Calf Raise", ["calves"], [], "bodyweight", "isolation", "beginner",
   ["Stand on one foot on a step, holding on for balance.",
    "Lower your heel below the step.",
    "Rise onto your toes as high as you can."],
   ["Hold a dumbbell to add load.", "Count reps per leg."],
   ["Bouncing.", "Bending the knee."],
   ["standing-calf-raise", "seated-calf-raise"], reps([10, 20, 30, 40]))

# ============================================================ ABS
ex("hanging-leg-raise", "Hanging Leg Raise", ["abdominals"], ["forearms"], "bodyweight", "isolation", "intermediate",
   ["Hang from a pull-up bar with straight arms.",
    "Raise your legs by curling your pelvis up.",
    "Lower slowly without swinging."],
   ["Bent knees make it easier.", "Think about curling the hips, not just lifting the legs."],
   ["Swinging for momentum.", "Only lifting the legs to hip height."],
   ["cable-crunch", "ab-wheel-rollout", "crunch"], reps([5, 12, 20, 28]))
ex("cable-crunch", "Cable Crunch", ["abdominals"], [], "cable", "isolation", "beginner",
   ["Kneel facing a high pulley holding a rope beside your head.",
    "Crunch down by curling your ribs toward your hips.",
    "Return slowly."],
   ["Keep the hips still; only the spine moves.", "Exhale hard at the bottom."],
   ["Sitting back on the heels to pull with the hips.", "Pulling with the arms."],
   ["machine-crunch", "hanging-leg-raise", "crunch"], load([0.3, 0.5, 0.75, 1.0], MACHINE))
ex("machine-crunch", "Ab Crunch Machine", ["abdominals"], [], "machine", "isolation", "beginner",
   ["Sit in the machine with the pads on your chest or the handles in hand.",
    "Curl your torso forward and down.",
    "Return slowly."],
   ["Lets you add load progressively.", "Move through the spine, not the hips."],
   ["Using momentum.", "Pulling with the arms."],
   ["cable-crunch", "crunch"], load([0.3, 0.55, 0.8, 1.05], MACHINE))
ex("crunch", "Crunch", ["abdominals"], [], "bodyweight", "isolation", "beginner",
   ["Lie on your back with knees bent and hands by your temples.",
    "Curl your shoulders off the floor toward your hips.",
    "Lower slowly."],
   ["Exhale as you curl up.", "Keep your chin off your chest."],
   ["Yanking the head with the hands.", "Sitting all the way up with the hip flexors."],
   ["cable-crunch", "hanging-leg-raise"], reps([20, 40, 60, 80]))
ex("ab-wheel-rollout", "Ab Wheel Rollout", ["abdominals"], ["lowerBack", "shoulders"], "bodyweight", "compound", "advanced",
   ["Kneel holding an ab wheel under your shoulders.",
    "Roll forward slowly, keeping your back from sagging.",
    "Go as far as you can control, then pull back with your abs."],
   ["Roll toward a wall to limit range while learning.", "Squeeze your glutes."],
   ["Lower back sagging.", "Leading with the hips on the way back."],
   ["hanging-leg-raise", "cable-crunch"], reps([3, 10, 20, 30]))
ex("cable-woodchop", "Cable Woodchop", ["abdominals"], ["shoulders"], "cable", "compound", "beginner",
   ["Set a pulley high and stand side-on, holding the handle with both hands.",
    "Pull the handle diagonally down across your body, rotating through your torso.",
    "Return slowly and repeat, then switch sides."],
   ["Pivot your back foot.", "Keep the arms fairly straight."],
   ["Pulling with only the arms.", "Twisting the lower back without moving the hips."],
   ["cable-crunch", "russian-twist"], ("none", [], "Rotation loads aren't comparable enough to rank.")),
ex("russian-twist", "Russian Twist", ["abdominals"], [], "bodyweight", "isolation", "beginner",
   ["Sit with knees bent and lean back slightly.",
    "Rotate your torso to touch the floor beside each hip.",
    "Count each side as one rep."],
   ["Hold a plate to add load.", "Lift your feet to make it harder."],
   ["Rounding the back.", "Only moving the arms."],
   ["cable-woodchop", "crunch"], reps([20, 40, 60, 80]))



def expand(t, whole):
    """Four anchors -> seven thresholds, mirroring RankingStandard.upgradeLegacy in the app."""
    b, si, go, el = t
    gap = el - go
    out = [b, si, go, go + gap / 3, go + 2 * gap / 3, el, el + gap / 2]
    if whole:
        out = [float(round(v)) for v in out]
        for i in range(1, len(out)):
            if out[i] <= out[i - 1]:
                out[i] = out[i - 1] + 1
    else:
        out = [round(v, 3) for v in out]
    return out


def add_new():
    for n in guides.NEW:
        method, t, note = n["ranking"]
        E.append({
            "slug": n["slug"], "name": n["name"], "primary": n["primary"], "secondary": n["secondary"],
            "equipment": n["equipment"], "mechanic": n["mechanic"], "difficulty": n["difficulty"],
            "instructions": n["steps"], "tips": n["form"], "mistakes": [], "alternatives": n["alternatives"],
            "ranking": {"method": method, "thresholds": t, "note": NOTES[note]},
        })


def finish():
    for e in E:
        gd = guides.G.get(e["slug"])
        if gd is None:
            continue
        if gd["pm"] is not None:
            e["primary"] = gd["pm"]
        if gd["sm"] is not None:
            e["secondary"] = gd["sm"]
        breathing, base_safety = guides.PATTERNS[gd["p"]]
        tracking = gd["t"] or ("reps" if e["equipment"] == "bodyweight" else "weightReps")
        e["mistakes"] = [m[0] for m in gd["m"]]
        e["guide"] = {
            "overview": gd["o"], "setup": gd["s"], "steps": e["instructions"], "form": e["tips"],
            "breathing": breathing,
            "mistakes": [{"what": w, "why": y, "fix": f} for (w, y, f) in gd["m"]],
            "safety": gd["sf"] + base_safety + [guides.UNIVERSAL_SAFETY],
            "easier": gd["e"], "harder": gd["h"], "pattern": gd["p"], "unilateral": gd["u"], "tracking": tracking,
        }
        r = e["ranking"]
        if tracking == "time":
            e["ranking"] = {"method": "none", "thresholds": [], "note": TIMED}
        elif r["method"] in ("load", "reps") and len(r["thresholds"]) == 4:
            r["thresholds"] = expand(r["thresholds"], r["method"] == "reps")


def validate():
    slugs = [e["slug"] for e in E]
    assert len(slugs) == len(set(slugs)), "duplicate slugs"
    names = [e["name"] for e in E]
    assert len(names) == len(set(names)), "duplicate names"
    errors = []
    for e in E:
        for m in e["primary"] + e["secondary"]:
            if m not in MUSCLES:
                errors.append(f"{e['slug']}: bad muscle {m}")
        if not e["primary"]:
            errors.append(f"{e['slug']}: no primary muscle")
        if set(e["primary"]) & set(e["secondary"]):
            errors.append(f"{e['slug']}: muscle listed as primary and secondary")
        if e["equipment"] not in EQUIPMENT:
            errors.append(f"{e['slug']}: bad equipment")
        for a in e["alternatives"]:
            if a not in slugs:
                errors.append(f"{e['slug']}: unknown alternative {a}")
            if a == e["slug"]:
                errors.append(f"{e['slug']}: lists itself")
        r = e["ranking"]
        if r["method"] in ("load", "reps"):
            t = r["thresholds"]
            if len(t) != 7 or any(b <= a for a, b in zip(t, t[1:])) or t[0] <= 0:
                errors.append(f"{e['slug']}: bad thresholds {t}")
        elif r["method"] != "none":
            errors.append(f"{e['slug']}: bad method")
        if e["equipment"] == "band" and r["method"] != "none":
            errors.append(f"{e['slug']}: bands are unranked")
        if e["equipment"] == "bodyweight" and r["method"] == "load":
            errors.append(f"{e['slug']}: bodyweight exercises rank on reps")
        gd = e.get("guide")
        if not gd:
            errors.append(f"{e['slug']}: missing guide")
            continue
        if not gd["overview"] or len(gd["steps"]) < 2 or not gd["form"] or not gd["setup"] or not gd["breathing"]:
            errors.append(f"{e['slug']}: incomplete guide")
        if len(gd["mistakes"]) < 2 or any(not (m["what"] and m["why"] and m["fix"]) for m in gd["mistakes"]):
            errors.append(f"{e['slug']}: mistakes need what, why and fix")
        if not gd["safety"] or not gd["easier"] or not gd["harder"]:
            errors.append(f"{e['slug']}: missing safety or variations")
        if gd["tracking"] == "time" and r["method"] != "none":
            errors.append(f"{e['slug']}: timed exercises are unranked")
    covered = {m for e in E for m in e["primary"]}
    missing = MUSCLES - covered
    if missing:
        errors.append(f"muscles with no primary exercise: {missing}")
    covered_eq = {e["equipment"] for e in E}
    if EQUIPMENT - covered_eq:
        errors.append(f"equipment unused: {EQUIPMENT - covered_eq}")
    unknown = set(guides.G) - set(slugs)
    if unknown:
        errors.append(f"guides for unknown slugs: {unknown}")
    if errors:
        raise SystemExit("\n".join(errors))


def template_slugs():
    """Every slug used by a workout template in SplitPresets.swift must exist."""
    import re
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "..", "PRIME", "Domain", "SplitPresets.swift")) as f:
        text = f.read()
    return set(re.findall(r'\("([a-z0-9-]+)", \d+, \d+\)', text))


if __name__ == "__main__":
    add_new()
    finish()
    validate()
    missing = template_slugs() - {e["slug"] for e in E}
    if missing:
        raise SystemExit(f"templates use unknown exercises: {sorted(missing)}")
    out = {"version": VERSION, "exercises": E}
    with open(sys.argv[1], "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    from collections import Counter
    print(len(E), "exercises")
    print("by equipment:", dict(Counter(e["equipment"] for e in E)))
    print("by primary muscle:", dict(Counter(m for e in E for m in e["primary"])))
    print("ranking:", dict(Counter(e["ranking"]["method"] for e in E)))
    print("timed:", [e["slug"] for e in E if e["guide"]["tracking"] == "time"])
