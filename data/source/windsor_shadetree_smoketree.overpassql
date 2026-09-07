// Fire Truck Game: the one-time OpenStreetMap pull behind
// resources/windsor_shadetree.tres. Data (c) OpenStreetMap contributors,
// available under the Open Database License (ODbL).
//
// Area: a 500 m x 380 m box centred on the junction of Shadetree Drive with
// Smoketree Street and Smoketree Court, Windsor, California 95492.
// Centre: 38.5439893, -122.7953823
// Box (south, west, north, east): 38.5422777, -122.7982498, 38.5457009, -122.7925148
//
// Endpoint: https://overpass-api.de/api/interpreter
// Response committed verbatim as windsor_shadetree_smoketree.json.
// The game never calls this at runtime; see ATTRIBUTION.md.
[out:json][timeout:180];
(
  way["highway"](38.5422777,-122.7982498,38.5457009,-122.7925148);
  way["building"](38.5422777,-122.7982498,38.5457009,-122.7925148);
  node["emergency"="fire_hydrant"](38.5422777,-122.7982498,38.5457009,-122.7925148);
  node["amenity"="fire_station"](around:1500,38.5439893,-122.7953823);
  way["amenity"="fire_station"](around:1500,38.5439893,-122.7953823);
);
out body geom;
