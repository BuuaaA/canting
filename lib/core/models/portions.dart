/// Six food-group portions used throughout the core engine.
class Portions {
  const Portions({
    this.grains = 0,
    this.vegetables = 0,
    this.fruits = 0,
    this.protein = 0,
    this.proteinSoy = 0,
    this.oil = 0,
  });

  static const zero = Portions();

  final double grains;
  final double vegetables;
  final double fruits;
  final double protein;
  final double proteinSoy;
  final double oil;

  factory Portions.fromJson(Map<String, dynamic> json) {
    double readNumber(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return Portions(
      grains: readNumber('grains'),
      vegetables: readNumber('vegetables'),
      fruits: readNumber('fruits'),
      protein: readNumber('protein'),
      proteinSoy: readNumber('protein_soy'),
      oil: json.containsKey('oil') ? readNumber('oil') : readNumber('oil_base'),
    );
  }

  Map<String, double> toJson() => {
    'grains': grains,
    'vegetables': vegetables,
    'fruits': fruits,
    'protein': protein,
    'protein_soy': proteinSoy,
    'oil': oil,
  };

  Map<String, double> toDishJson() => {
    'grains': grains,
    'vegetables': vegetables,
    'fruits': fruits,
    'protein': protein,
    'protein_soy': proteinSoy,
    'oil_base': oil,
  };

  Map<String, double> get byCategory => {
    'grains': grains,
    'vegetables': vegetables,
    'fruits': fruits,
    'protein': protein,
    'protein_soy': proteinSoy,
    'oil': oil,
  };

  double valueFor(String category) => switch (category) {
    'grains' => grains,
    'vegetables' => vegetables,
    'fruits' => fruits,
    'protein' => protein,
    'protein_soy' => proteinSoy,
    'oil' => oil,
    _ => 0,
  };

  Portions scale(double factor) => Portions(
    grains: grains * factor,
    vegetables: vegetables * factor,
    fruits: fruits * factor,
    protein: protein * factor,
    proteinSoy: proteinSoy * factor,
    oil: oil * factor,
  );

  Portions operator +(Portions other) => Portions(
    grains: grains + other.grains,
    vegetables: vegetables + other.vegetables,
    fruits: fruits + other.fruits,
    protein: protein + other.protein,
    proteinSoy: proteinSoy + other.proteinSoy,
    oil: oil + other.oil,
  );
}
