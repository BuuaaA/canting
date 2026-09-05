import 'models/food_knowledge.dart';
import 'dish_matcher.dart';
import 'models/local_food.dart';
import 'models/meal_record.dart';

/// Exact identity alone is automatic. Every approximate result is a candidate.
/// Numeric similarities in the legacy matcher are scores, not probabilities.
class LocalFoodMatcher {
  LocalFoodMatcher(this.legacy, this.profiles);
  final DishMatcher? legacy;
  final List<LocalFoodProfile> profiles;
  MealDish resolve(MealDish input, {String brand = ''}) {
    final previous = input.food;
    if (previous != null &&
        (previous.brandOrigin != 'merchant' ||
            previous.merchantContext == brand)) {
      return input;
    }
    // Re-decide identity, retaining only this order's inputs, never its old category.
    final resolved = _resolve(
      input,
      brand: brand,
      spec: previous?.spec ?? OrderSpec.parse(input.name),
    );
    return resolved.food == null
        ? resolved
        : resolved.copyWith(
            food: resolved.food!.withBrandContext('merchant', brand),
          );
  }

  MealDish _resolve(
    MealDish input, {
    required String brand,
    required OrderSpec spec,
  }) {
    final name = OrderSpec.productName(input.name);
    final key = FoodFacts(brand: brand, name: name).key;
    final exactMatches = profiles
        .where(
          (p) =>
              p.facts.key == key ||
              (FoodFacts.normalize(p.facts.brand) ==
                      FoodFacts.normalize(brand) &&
                  p.rawNames.any(
                    (n) =>
                        FoodFacts.normalize(OrderSpec.productName(n)) ==
                        FoodFacts.normalize(name),
                  )),
        )
        .toList();
    final exact = exactMatches.length == 1 ? exactMatches.single : null;
    if (exact != null && !OrderSpec.ambiguous(input.name)) {
      final explicitPrep = input.name.contains('油炸')
          ? 'fried'
          : input.name.contains('清蒸')
          ? 'steamed'
          : 'unknown';
      final conflict =
          explicitPrep != 'unknown' &&
          exact.facts.preparation != 'unknown' &&
          explicitPrep != exact.facts.preparation;
      return MealDish(
        name: input.name,
        quantity: input.quantity,
        contributionsKnown: false,
        food: FoodObservation(
          rawName: input.name,
          facts: conflict ? FoodFacts(brand: brand, name: name) : exact.facts,
          spec: spec,
          suggestion: exact.lastSpec,
          matchedBy: 'local_exact',
          decision: conflict ? FoodDecision.candidate : FoodDecision.autoFill,
          candidateName: conflict ? exact.facts.name : null,
        ),
      );
    }
    final candidates = profiles
        .where(
          (p) =>
              (FoodFacts.normalize(p.facts.name) == FoodFacts.normalize(name) ||
              (FoodFacts.normalize(name).length >= 2 &&
                  DishMatcher.nameSimilarity(
                        FoodFacts.normalize(p.facts.name),
                        FoodFacts.normalize(name),
                      ) >=
                      FoodMatchPolicy.candidateSimilarity) ||
              (FoodFacts.normalize(name).length >= 2 &&
                  (FoodFacts.normalize(p.facts.name)
                          .contains(FoodFacts.normalize(name)) ||
                      FoodFacts.normalize(name)
                          .contains(FoodFacts.normalize(p.facts.name))))),
        )
        .toList();
    // P1 package has no independent brand field: never assume a branded recipe.
    final knowledgeMatches =
        (legacy?.foodDatabase.knowledgePackage?.records ?? <FoodKnowledge>[])
            .where((k) {
              final aliases = (k.toJson()['aliases'] as List).cast<String>();
              return [k.name, ...aliases].any(
                (alias) =>
                    FoodFacts.normalize(OrderSpec.productName(alias)) ==
                    FoodFacts.normalize(name),
              );
            })
            .toList();
    if (knowledgeMatches.isNotEmpty && candidates.isEmpty && brand.isEmpty) {
      bool fits(FoodKnowledge k) {
        bool field(String actual, String expected) =>
            expected == 'unknown' ||
            expected == 'notApplicable' ||
            actual == expected;
        return field(spec.sugar, k.sugarLevel) &&
            field(spec.cup == 'medium' ? 'regular' : spec.cup, k.cupSize) &&
            field(spec.size == 'normal' ? 'regular' : spec.size, k.sizeBucket);
      }

      final variants = knowledgeMatches.where(fits).toList();
      final auto = variants.length == 1 && !OrderSpec.ambiguous(input.name);
      final k = auto ? variants.single : null;
      return MealDish(
        name: input.name,
        quantity: input.quantity,
        contributionsKnown: false,
        food: FoodObservation(
          rawName: input.name,
          facts: FoodFacts(
            name: name,
            category: k == null
                ? 'unknown'
                : k.productCategory == 'beverage' &&
                      ['milk_tea', 'coffee'].contains(k.beverageType)
                ? k.beverageType
                : k.productCategory,
            preparation: k?.preparation ?? 'unknown',
          ),
          spec: spec,
          knowledge: k,
          matchedBy: auto
              ? 'knowledge_variant_exact'
              : 'knowledge_variant_candidate',
          decision: auto ? FoodDecision.autoFill : FoodDecision.candidate,
          candidateName: auto
              ? null
              : knowledgeMatches.map((k) => k.name).join(' / '),
        ),
      );
    }
    final match = legacy?.match([input.name]).single;
    // A branded input cannot silently borrow a generic or another brand recipe.
    if (brand.isEmpty &&
        candidates.isEmpty &&
        !OrderSpec.ambiguous(input.name) &&
        match?.shouldAutoAdd == true &&
        spec.sugar == 'unknown' &&
        spec.cup == 'unknown' &&
        !RegExp(r'\d+\s*寸').hasMatch(input.name)) {
      return MealDish(
        name: input.name,
        quantity: input.quantity,
        portionSize: input.portionSize,
        matchedDishId: match!.matchedDishId,
        matchConfidence: match.confidence,
        portions: legacy!.calculatePortions(match, input.portionSize),
      );
    }
    return MealDish(
      name: input.name,
      quantity: input.quantity,
      contributionsKnown: false,
      food: FoodObservation(
        rawName: input.name,
        facts: FoodFacts(brand: brand, name: name),
        spec: spec,
        matchedBy: candidates.isNotEmpty
            ? 'brand_conflict'
            : match?.matchType.name ?? 'unmatched',
        decision:
            exactMatches.length > 1 ||
                candidates.isNotEmpty ||
                match?.isMatched == true
            ? FoodDecision.candidate
            : FoodDecision.manual,
        candidateName: candidates.isNotEmpty
            ? '${candidates.first.facts.brand} ${candidates.first.facts.name}'
            : match?.isMatched == true
            ? match!.matchedDishName
            : null,
      ),
    );
  }
}
