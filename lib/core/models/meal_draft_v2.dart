import 'dart:convert';

import '../../services/recognition_contract.dart';
import '../serving_estimator.dart';
import '../completion_calculator.dart';
import 'daily_intake.dart';
import 'meal_record.dart';
import 'portions.dart';

/// Validated local review state. Copies on both boundaries prevent edits bypassing
/// revision/history. Transport results enter through fromResponse, UI uses commands.
class MealDraftV2 {
  MealDraftV2(
    this.contract,
    Map<String, dynamic> draft, {
    required this.simulated,
  }) : _draft = contract.draft(draft) {
    if (!simulated &&
        (_draft['modelVersion'] as String? ?? '').startsWith('mock-')) {
      throw const FormatException('SIMULATED_MARKER_REQUIRED');
    }
  }

  factory MealDraftV2.fromResponse(
    RecognitionContract contract,
    Map<String, dynamic> request,
    Map<String, dynamic> response,
  ) {
    final checked = contract.response(response, contract.request(request));
    if (checked['state'] != 'review') {
      throw const FormatException('NO_REVIEW_RESULT');
    }
    return MealDraftV2(
      contract,
      checked['result'] as Map<String, dynamic>,
      simulated: checked['simulated'] as bool,
    );
  }

  factory MealDraftV2.fromMeal(RecognitionContract contract, MealRecord meal) {
    final snapshot = meal.recognitionSnapshot;
    if (snapshot == null || snapshot['schemaVersion'] != 'meal-v2.2') {
      throw const FormatException('NOT_A_V2_MEAL');
    }
    final result = MealDraftV2(
      contract,
      Map<String, dynamic>.from(snapshot['draft'] as Map),
      simulated: snapshot['simulated'] as bool,
    );
    result._history.addAll(
      (snapshot['editHistory'] as List).map((e) => _copy(e as Map)),
    );
    return result;
  }

  final RecognitionContract contract;
  final bool simulated;
  Map<String, dynamic> _draft;
  final List<Map<String, dynamic>> _history = [];
  Map<String, dynamic> get draft => _copy(_draft);
  String get draftId => _draft['draftId'] as String;
  int get revision => _draft['draftRevision'] as int;
  List<Map<String, dynamic>> get history =>
      _history.map(_copy).toList(growable: false);

  static Map<String, dynamic> _copy(Map value) =>
      (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
  static Map<String, dynamic> fact(dynamic value) => {
    'value': value,
    'provenance': value == null ? 'unknown' : 'user_input',
    'reviewStatus': value == null ? 'unreviewed' : 'accepted',
    'evidenceRefs': <String>[],
  };
  Map _node(Map d, String id) {
    for (final Map p in d['products']) {
      if (p['productId'] == id) return p;
      for (final Map c in p['components']) {
        if (c['componentId'] == id) return c;
      }
    }
    throw const FormatException('UNKNOWN_NODE');
  }

  void _change(String nodeId, String field, void Function(Map) change) {
    final next = draft;
    final before = _copy(_node(next, nodeId));
    change(_node(next, nodeId));
    // Derive active flags together on every command: never preserve a stale path.
    for (final Map p in next['products']) {
      p['calculation']['active'] =
          p['selected'] == true && p['nutritionMode'] == 'aggregate';
      for (final Map c in p['components']) {
        c['calculation']['active'] =
            p['selected'] == true &&
            c['selected'] == true &&
            p['nutritionMode'] == 'children';
      }
    }
    next['draftRevision'] = revision + 1;
    final valid = contract.draft(next);
    _history.add({
      'revision': next['draftRevision'],
      'nodeId': nodeId,
      'field': field,
      'before': before,
      'after': _copy(_node(next, nodeId)),
      'editedAt': DateTime.now().toUtc().toIso8601String(),
    });
    _draft = valid;
  }

  void select(String nodeId, bool selected) =>
      _change(nodeId, 'selected', (n) => n['selected'] = selected);
  void setMode(String productId, String mode) =>
      _change(productId, 'nutritionMode', (n) => n['nutritionMode'] = mode);

  /// Accepting an inference preserves its provenance and original evidence.
  void reviewFact(String nodeId, String field, {bool accepted = true}) =>
      _change(nodeId, field, (n) {
        final f = n[field];
        if (f is! Map || !f.containsKey('provenance')) {
          throw const FormatException('NOT_A_FACT');
        }
        f['reviewStatus'] = accepted ? 'accepted' : 'rejected';
      });

  void editFact(String nodeId, String field, dynamic value) =>
      _change(nodeId, field, (n) {
        if (![
              'displayName',
              'rawName',
              'purchaseQuantity',
              'name',
              'categoryId',
            ].contains(field) ||
            !n.containsKey(field)) {
          throw const FormatException('NOT_EDITABLE_FACT');
        }
        n[field] = fact(value);
      });

  void addComponent(String productId, String name) =>
      _change(productId, 'components', (p) {
        final id = 'c-${DateTime.now().microsecondsSinceEpoch}';
        p['components'].add({
          'componentId': id,
          'selected': true,
          'name': fact(name),
          'categoryId': fact(null),
          'calculation': _emptyCalculation(),
          'completeness': 'unknown',
          'confidence': {'raw': null, 'calibrated': null, 'grade': 'unknown'},
        });
        p['nutritionMode'] = 'children';
      });

  void removeComponent(String productId, String componentId) =>
      _change(productId, 'components', (p) {
        p['components'].removeWhere((c) => c['componentId'] == componentId);
        if ((p['components'] as List).isEmpty) p['nutritionMode'] = 'unknown';
      });

  static Map<String, dynamic> _emptyCalculation() => {
    'active': false,
    'portionBasis': 'unknown',
    'portion': fact(null),
    'allocationRatio': fact(null),
    'consumedRatio': fact(null),
    'notEaten': fact(null),
    'estimateRange': fact(null),
  };

  /// Personal mode always clears previous allocation/consumption factors.
  void setIntake(
    String nodeId, {
    required String basis,
    Map<String, dynamic>? portion,
    double? allocation,
    double? consumed,
    bool notEaten = false,
  }) => _change(nodeId, 'calculation', (n) {
    n['calculation'] = {
      'active': n['calculation']['active'],
      'portionBasis': basis,
      'portion': fact(portion),
      'allocationRatio': fact(basis == 'personal_consumed' ? null : allocation),
      'consumedRatio': fact(basis == 'personal_consumed' ? null : consumed),
      'notEaten': fact(notEaten ? true : null),
      'estimateRange': fact(null),
    };
  });

  /// Saves an immutable graph plus the exact scalar subtotal used by existing
  /// 7/28-day consumers. No name/category fallback, new unit map or range midpoint.
  MealRecord toMeal({
    required String mealType,
    required DateTime timestamp,
    ServingEstimator? estimator,
    DailyIntake? dailyIntake,
    String? policyVersion,
    String? knowledgeVersion,
  }) {
    final d = contract.draft(_draft);
    final products = (d['products'] as List)
        .cast<Map>()
        .where((p) => p['selected'] == true)
        .toList();
    if (products.isEmpty) throw const FormatException('NO_SELECTED_FOOD');
    final amounts = contract.effectiveAmounts(d);
    final dishes = <MealDish>[];
    var mealTotal = Portions.zero;
    final contributions = <String, dynamic>{};
    final completeness = <String>[];
    for (final p in products) {
      final nodes = p['nutritionMode'] == 'aggregate'
          ? [p]
          : p['nutritionMode'] == 'children'
          ? (p['components'] as List)
                .cast<Map>()
                .where((c) => c['selected'] == true)
                .toList()
          : <Map>[];
      var subtotal = Portions.zero;
      var known = 0;
      var unknown = 0;
      for (final node in nodes) {
        final id = (node['componentId'] ?? node['productId']) as String;
        final Map c = node['calculation'];
        final Map name = node['name'] ?? node['displayName'];
        final amount = amounts[id];
        Portions? value;
        String? mapping;
        double? gramsPerServing;
        if (c['active'] == true &&
            (c['notEaten']['value'] == true || amount == 0)) {
          value = Portions.zero;
          mapping = 'user_not_eaten';
        } else if (amount != null &&
            name['reviewStatus'] == 'accepted' &&
            name['value'] != null) {
          final unit = PortionMeasureUnit.values
              .where((value) => value.name == c['portion']['value']?['unit'])
              .firstOrNull;
          final candidate = unit == null
              ? null
              : estimator?.convertIntake(
                  name['value'] as String,
                  amount: amount.toDouble(),
                  unit: unit,
                );
          final exactCandidate =
              candidate?.servings != null &&
                  candidate!.servings!.min == candidate.servings!.max
              ? candidate
              : null;
          final estimate = unit == PortionMeasureUnit.g
              ? estimator?.estimateServings(
                  name['value'] as String,
                  amount.toDouble(),
                )
              : null;
          final category = switch (estimate?.categoryKey) {
            'grain_tuber' => 'grains',
            'vegetable' => 'vegetables',
            'fruit' => 'fruits',
            'protein_meat_egg' => 'protein',
            'dairy' || 'dairy_products' => 'protein',
            'soy' || 'soy_products' => 'protein_soy',
            'oil' => 'oil',
            _ => switch (exactCandidate?.knowledge.categoryId) {
              'grain_tuber' => 'grains',
              'vegetable' => 'vegetables',
              'fruit' => 'fruits',
              'protein_meat_egg' || 'dairy' => 'protein',
              'soy' => 'protein_soy',
              'oil' => 'oil',
              _ => null,
            },
          };
          final servings =
              exactCandidate?.servings?.min ??
              (estimate?.basis == EstimateBasis.foodExchange
                  ? estimate?.servings
                  : null);
          if (servings != null && category != null) {
            value = Portions.fromKnownJson({
              for (final key in Portions.zero.toJson().keys)
                key: key == category ? servings : 0,
            });
            mapping =
                exactCandidate?.mapping ?? 'food_exchange:${name['value']}';
            gramsPerServing = estimate?.gramsPerDishServing;
          }
        }
        if (value == null) {
          unknown++;
        } else {
          known++;
          subtotal = subtotal + value;
        }
        node['completeness'] = value == null ? 'unknown' : 'known';
        contributions[id] = {
          'effectiveAmount': c['notEaten']['value'] == true ? null : amount,
          'unit': c['portion']['value']?['unit'],
          'notEaten': mapping == 'user_not_eaten',
          'portions': value?.toJson(),
          'mapping': mapping,
          'gramsPerServing': gramsPerServing,
          'contributionUnit': 'food_group_servings',
          'estimated': value != null && mapping != 'user_not_eaten',
        };
      }
      mealTotal = mealTotal + subtotal;
      final complete = nodes.isNotEmpty && unknown == 0;
      final status = complete
          ? 'known'
          : known > 0
          ? 'partial'
          : 'unknown';
      p['completeness'] = status;
      completeness.add(status);
      // One legacy-readable parent summary; known subtotal remains separate from
      // unknown remainder so existing engines retain known contributions.
      final name = p['displayName']['value'] as String? ?? '未命名食物';
      if (known > 0) {
        dishes.add(
          MealDish(name: simulated ? '[模拟] $name' : name, portions: subtotal),
        );
      }
      if (!complete) {
        dishes.add(
          MealDish(
            name: simulated ? '[模拟] $name（结构未知）' : '$name（结构未知）',
            contributionsKnown: false,
          ),
        );
      }
    }
    return MealRecord(
      mealId: draftId,
      mealType: mealType,
      timestamp: timestamp,
      dishes: dishes,
      portionsTotal: mealTotal,
      completionRate: dailyIntake == null
          ? 0
          : CompletionCalculator()
                .calculate(eatenPortions: mealTotal, dailyIntake: dailyIntake)
                .overall,
      recognitionSnapshot: {
        'schemaVersion': 'meal-v2.2',
        'wireVersion': 'recognition-n0.2',
        'simulated': simulated,
        'draft': d,
        'editHistory': history,
        'knowledgeVersion': knowledgeVersion,
        'policyVersion': policyVersion,
        'calculationVersion': 'personal-intake-n1.1',
        'contributions': contributions,
        'completeness': completeness.every((s) => s == 'known')
            ? 'known'
            : completeness.any((s) => s != 'unknown')
            ? 'partial'
            : 'unknown',
      },
    );
  }
}
