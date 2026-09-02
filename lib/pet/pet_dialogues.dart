import 'dart:convert';

import 'pet_data.dart';

class PetDialogues {
  PetDialogues(Map<String, dynamic> data)
    : _data = Map<String, dynamic>.unmodifiable(data) {
    for (final petType in PetData.supportedPetTypes) {
      if (!_data.containsKey(petType)) {
        throw FormatException('Missing dialogues for $petType');
      }
    }
  }

  factory PetDialogues.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Dialogue JSON must be an object');
    }
    return PetDialogues(decoded);
  }

  factory PetDialogues.defaults() => PetDialogues(_defaultDialogueData);

  final Map<String, dynamic> _data;

  String statusDialogue(String petType, VitalityState state) {
    return _text(petType, 'status', state.name);
  }

  String mealReactionDialogue(String petType, double completionRate) {
    _validateCompletionRate(completionRate);
    final key = switch (completionRate) {
      >= 0.8 => 'excellent',
      >= 0.6 => 'good',
      >= 0.4 => 'mid',
      >= 0.2 => 'poor',
      _ => 'very_poor',
    };
    return _text(petType, 'meal', key);
  }

  String gapDialogue(String petType, Map<String, double> completionByCategory) {
    final candidates = <({String key, double score})>[];

    void addLow(String key) {
      final value = completionByCategory[key];
      if (value != null && value < 0.4) {
        candidates.add((key: key, score: 0.4 - value));
      }
    }

    void addHigh(String key) {
      final value = completionByCategory[key];
      if (value != null && value > 1.2) {
        candidates.add((key: key, score: value - 1.2));
      }
    }

    addLow('vegetables');
    addLow('protein');
    addHigh('oil');
    addHigh('grains');
    final fruits = completionByCategory['fruits'];
    if (fruits != null && fruits == 0) {
      candidates.add((key: 'fruits', score: 0.4));
    }

    if (candidates.isNotEmpty) {
      var largest = candidates.first;
      for (final candidate in candidates.skip(1)) {
        if (candidate.score > largest.score) {
          largest = candidate;
        }
      }
      return _text(petType, 'gap', largest.key);
    }

    final isBalanced =
        completionByCategory.isNotEmpty &&
        completionByCategory.values.every((value) => value >= 0.7);
    return _text(petType, 'gap', isBalanced ? 'balanced' : 'general');
  }

  String continuousDialogue(String petType, String behaviorCode) {
    return _text(petType, 'continuous', behaviorCode);
  }

  Iterable<String> get allTexts sync* {
    for (final petType in PetData.supportedPetTypes) {
      final petData = _petData(petType);
      for (final section in petData.values) {
        if (section is Map<String, dynamic>) {
          yield* section.values.cast<String>();
        }
      }
    }
  }

  String _text(String petType, String section, String key) {
    final petData = _petData(petType);
    final sectionData = petData[section];
    if (sectionData is! Map<String, dynamic>) {
      throw FormatException('Missing dialogue section: $petType.$section');
    }
    final text = sectionData[key];
    if (text is! String) {
      throw FormatException('Missing dialogue: $petType.$section.$key');
    }
    return text;
  }

  Map<String, dynamic> _petData(String petType) {
    if (!PetData.supportedPetTypes.contains(petType)) {
      throw ArgumentError.value(petType, 'petType', 'Unsupported pet type');
    }
    final petData = _data[petType];
    if (petData is! Map<String, dynamic>) {
      throw FormatException('Invalid dialogues for $petType');
    }
    return petData;
  }

  static void _validateCompletionRate(double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw RangeError.range(value, 0, 1, 'completionRate');
    }
  }
}

const Map<String, dynamic> _defaultDialogueData = {
  'cat': {
    'status': {
      'energetic': '今天也精神满满！',
      'good': '哼，状态还不错',
      'low': '想吃点新鲜的…',
      'expecting': '今天吃了什么呀？',
    },
    'meal': {
      'excellent': '好均衡！哼，还行',
      'good': '嗯，吃得不错嘛～',
      'mid': '吃饱了～',
      'poor': '好像缺点什么…',
      'very_poor': '下次吃点菜好吗？',
    },
    'gap': {
      'vegetables': '今天没有绿色呢…',
      'protein': '还想吃点肉肉…',
      'oil': '有点油，想喝水…',
      'grains': '米饭有点多啦',
      'fruits': '今天没吃水果呢',
      'balanced': '哼，今天很均衡嘛～',
      'general': '下餐换个花样吧',
    },
    'continuous': {
      'good_meals_3': '最近吃得很棒嘛',
      'bad_meals_3': '下餐换个花样好吗？',
      'no_record_days_3': '好久不见，吃了啥？',
    },
  },
  'dog': {
    'status': {
      'energetic': '今天也活力满满！',
      'good': '状态不错，开心！',
      'low': '想吃点新鲜菜菜',
      'expecting': '今天吃了什么呀？',
    },
    'meal': {
      'excellent': '哇！均衡又好吃！',
      'good': '吃得不错，好开心！',
      'mid': '吃饱啦！',
      'poor': '好像还缺一点…',
      'very_poor': '下次吃点菜好吗？',
    },
    'gap': {
      'vegetables': '想吃绿色菜菜！',
      'protein': '还想吃点肉肉！',
      'oil': '嘴巴油油，想喝水',
      'grains': '饭饭多，想吃别的',
      'fruits': '甜甜的水果呢？',
      'balanced': '今天最棒啦！汪！',
      'general': '下餐换个花样吧！',
    },
    'continuous': {
      'good_meals_3': '连续三餐都很棒',
      'bad_meals_3': '换个花样好不好？',
      'no_record_days_3': '好久不见，吃了啥？',
    },
  },
  'hamster': {
    'status': {
      'energetic': '今天元气满满～',
      'good': '嗯嗯，状态不错～',
      'low': '想囤点新鲜食物…',
      'expecting': '今天吃了什么呀？',
    },
    'meal': {
      'excellent': '嗯嗯，好均衡呀～',
      'good': '吃得不错，好满足～',
      'mid': '嗯嗯，吃饱了～',
      'poor': '好像缺点什么…',
      'very_poor': '下次吃点菜好吗？',
    },
    'gap': {
      'vegetables': '绿色的好像没吃到',
      'protein': '蛋白质好像不太够',
      'oil': '有点腻腻的…',
      'grains': '主食好多，吃不下',
      'fruits': '想吃点甜甜的…',
      'balanced': '今天好满足呀～',
      'general': '下餐换个花样吧…',
    },
    'continuous': {
      'good_meals_3': '连续三餐都很棒',
      'bad_meals_3': '换个花样好不好？',
      'no_record_days_3': '好久不见，吃了啥？',
    },
  },
};
