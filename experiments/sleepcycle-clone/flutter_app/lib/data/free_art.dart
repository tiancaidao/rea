/// Cover photos for sleep-aid items and programs: CC0 photos from Wikimedia
/// Commons (see assets/free/CREDITS.md), 600 px webp. Items without an entry
/// keep their procedural [SceneArt] cover, which is also the fallback if a
/// file is missing.
const _dir = 'assets/free/images/covers/';

const sleepAidCovers = <String, String>{
  // Breathing
  'slow-exhale': '${_dir}lake_dusk.webp',
  'box-breath': '${_dir}sky_clouds.webp',
  'body-soften': '${_dir}pink_clouds.webp',
  // Ambience
  'rain-wind': '${_dir}rain_window.webp',
  'dawn': '${_dir}dawn_trees.webp',
  'drops': '${_dir}leaf_drops.webp',
  'fire': '${_dir}campfire.webp',
  'forest': '${_dir}moon_trees.webp',
  'brown': '${_dir}sand_ripples.webp',
  'pink': '${_dir}cloud_sunset.webp',
  'swell': '${_dir}ocean_wave.webp',
  // Stories
  'whale-throat': '${_dir}whale.webp',
  'camel-hump': '${_dir}camels.webp',
  'peter-rabbit': '${_dir}garden_flowers.webp',
  // Music
  'low-tide': '${_dir}piano_keys.webp',
  'drift': '${_dir}milky_way.webp',
  // ASMR
  'pages': '${_dir}book_window.webp',
  'brush': '${_dir}paint_brushes.webp',
  'tapping': '${_dir}candles.webp',
  'window': '${_dir}rain_bokeh.webp',
  // Winter evenings
  'first-snow': '${_dir}snow_cabin.webp',
  'long-night': '${_dir}village_night.webp',
  // Spatial audio
  'sp-rain': '${_dir}forest_stream.webp',
  'sp-shore': '${_dir}sailboats_sunset.webp',
  'sp-forest': '${_dir}moon_branches.webp',
  'sp-fire': '${_dir}campfire.webp',
  // Classical
  'nocturne': '${_dir}moon_sea.webp',
  'strings': '${_dir}violin.webp',
  // Bedtime rhymes
  'rock-a-by': '${_dir}milky_way_lake.webp',
  'wynken': '${_dir}full_moon.webp',
  'sugar-plum': '${_dir}plum_blossom.webp',
  'child-alone': '${_dir}blue_flowers.webp',
  // Guides
  'body-scan': '${_dir}snowy_forest.webp',
  'let-go': '${_dir}sunset_sky.webp',
};

const programCovers = <String, String>{
  'coaching': '${_dir}night_mountains.webp',
  'stress': '${_dir}lake_dusk.webp',
  'daytime': '${_dir}misty_mountain.webp',
  'mind': '${_dir}crescent_pines.webp',
  'bedroom': '${_dir}pillows.webp',
  'screens': '${_dir}rain_bokeh.webp',
  'parents': '${_dir}teddy_bear.webp',
};
