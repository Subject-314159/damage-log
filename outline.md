# User requirements

- I want to see in which areas a lot of walls are being destroyed
- I want to see which turret on my spaceship gets damaged/destroyed a lot
- I want to see which turret(s) deal the most damage and/or kill the most enemies
- I want to see in which areas the most damage is being dealt
- I want to be warned of potential breaches

# High level requirements

## Show heatmap of damage

- Log the total damage per tile, decayed over time
- Default decay over half an hour, adjustable via global map setting

## Calculate clusters of high impact

- Do some math magic to cluster adjacent areas

## Alert player on high risk areas

- Show a toggleable sidebar topleft that shows areas with high risk
- Have a threshold for the total damage
- Have a threshold for the number of entities destroyed in a certain timeframe
- Players can quickly open a camera at the specified location

## Detailed analysis per area

- Have a selection tool to analyze a certain area
- Or have an overall GUI with high risk areas
- Display a GUI with detailed stats

## Alert player on breaches

### Use case: Biters tear down the base
- We should define low impact, medium impact and high impact entities
- Low impact: Default defenses such as turrets, walls
- Medium impact: Everything not low or high impact
- High impact: Power infrastructure

### Use case: Biters suddenly breach defense lines
- We should measure control limits
- If at a certain point there is a spike in certain unit deaths we could imply a breach

### Use case: Biters attack inside of base without turret coverage
- When entities are being damaged we can scan the surrounding for turrets
- If there are no turrets in range we can notify the player