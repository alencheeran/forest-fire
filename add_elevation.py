import pandas as pd
import numpy as np

# Load existing dataset
df = pd.read_csv('data/forestfires.csv')

# Generate synthetic elevation data
# Fires are often correlated with certain elevations, but for the sake of this ML model,
# we will generate random elevation data between 200m and 1500m.
# We will add a slight correlation: higher elevation = slightly more wind and less temp, 
# but simply generating random is fine for this proof of concept.
np.random.seed(42)
df['elevation'] = np.random.randint(200, 1501, size=len(df))

# Save the augmented dataset
df.to_csv('data/forestfires.csv', index=False)
print("Successfully added synthetic 'elevation' data to data/forestfires.csv")
