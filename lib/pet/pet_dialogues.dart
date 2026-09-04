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

  /// 模块 7：按当日场景随机取一句文案（daily 区块，每种场景 ≥3 条）。
  ///
  /// 场景键：fulfilled / gap_vegetables / gap_protein / gap_fruits /
  /// gap_grains / gap_oil / no_record / morning / midday / afternoon /
  /// evening / night。
  List<String> dailyLines(String petType, String key) {
    final petData = _petData(petType);
    final section = petData['daily'];
    if (section is! Map<String, dynamic>) {
      throw FormatException('Missing dialogue section: $petType.daily');
    }
    final lines = section[key];
    if (lines is! List || lines.length < 3) {
      throw FormatException(
        'Missing or too-short daily dialogue: $petType.daily.$key',
      );
    }
    return List.unmodifiable(lines.cast<String>());
  }

  Iterable<String> get allTexts sync* {
    for (final petType in PetData.supportedPetTypes) {
      final petData = _petData(petType);
      for (final section in petData.values) {
        if (section is Map<String, dynamic>) {
          for (final value in section.values) {
            if (value is String) {
              yield value;
            } else if (value is List) {
              yield* value.whereType<String>();
            }
          }
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

  /// 原始数据快照，供测试比对默认数据与资产 JSON。
  Map<String, dynamic> toJsonSafe() => _data;

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
    'daily': {
      'fulfilled': ['哼，今天很均衡嘛', '这样吃才对嘛', '本喵勉强满意', '继续保持哦，哼'],
      'gap_vegetables': ['绿色的呢？想吃', '想吃菜菜…哼', '蔬菜有点少哦', '下餐补点绿色吧'],
      'gap_protein': ['还想吃点肉肉', '肉肉去哪了…', '蛋白质不够哦', '下餐来点肉嘛'],
      'gap_fruits': ['甜甜的水果呢', '今天没吃水果', '来点水果嘛…', '想吃果果了'],
      'gap_grains': ['米饭有点多啦', '主食过量了哦', '少来点饭饭嘛', '饭饭超标啦'],
      'gap_oil': ['有点油，想喝水', '嘴巴油油的…', '太油啦，哼', '清淡点好不好'],
      'no_record': ['今天吃了什么呀', '饿饿…想吃饭', '记录一下嘛', '今天还没开饭？'],
      'morning': ['早上好呀，人类', '早餐吃了吗？', '新的一天开始啦', '早安，记得吃饭'],
      'midday': ['中午吃点好的', '午餐时间到啦', '干饭时间到！', '中午吃什么呀'],
      'afternoon': ['下午吃点水果', '下午茶时间～', '困了…补充能量', '下午别饿肚子'],
      'evening': ['晚上想吃啥呢', '晚餐要吃蔬菜哦', '晚上别吃太油', '晚餐时间到啦'],
      'night': ['晚安，明天再见', '早点休息呀～', '困了…晚安', '明天也要好好吃饭'],
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
    'daily': {
      'fulfilled': ['今天最棒啦！汪！', '哇！均衡又好吃！', '全都在目标里！汪', '继续保持哦！汪！'],
      'gap_vegetables': ['想吃绿色菜菜！', '菜菜去哪了？汪', '蔬菜不够哦！汪', '下餐加菜好不好'],
      'gap_protein': ['还想吃点肉肉！', '肉肉不够呀…汪', '来点肉肉嘛！汪', '蛋白质要补够！'],
      'gap_fruits': ['甜甜的水果呢？', '今天没吃水果！', '想吃果果！汪！', '水果补一补嘛'],
      'gap_grains': ['饭饭有点多啦', '主食超标了哦！', '饭饭太多啦，汪', '少盛点饭嘛'],
      'gap_oil': ['嘴巴油油想喝水', '太油啦，汪！', '清淡点好不好', '油油的难受…'],
      'no_record': ['今天吃了什么呀', '汪！肚子饿了', '快记录一下嘛', '今天还没开饭？'],
      'morning': ['早上好！汪！', '早餐吃了吗？汪', '新的一天，冲！', '早安！一起加油'],
      'midday': ['午餐时间到！汪', '中午吃什么呀', '干饭时间到！汪', '中午要吃蔬菜哦'],
      'afternoon': ['下午吃点水果', '下午茶！汪！', '出去走走吧！', '补充点能量～'],
      'evening': ['晚餐时间到！汪', '晚上想吃啥呢', '晚餐要吃蔬菜哦', '晚上别吃太油哦'],
      'night': ['晚安！汪！', '早点休息呀～', '做个好梦，汪', '明天也要好好吃饭'],
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
    'daily': {
      'fulfilled': ['今天好满足呀～', '嗯嗯，很均衡～', '饱饱的，开心～', '继续加油哦～'],
      'gap_vegetables': ['绿色的没吃到…', '想吃点菜菜…', '蔬菜有点少哦…', '下餐加点菜嘛'],
      'gap_protein': ['蛋白质不太够…', '想吃点肉肉…', '补点蛋白质嘛…', '肉肉去哪了…'],
      'gap_fruits': ['想吃点甜甜的…', '今天没吃水果…', '来点水果嘛～', '果果在哪呀…'],
      'gap_grains': ['主食好多吃不下', '米饭有点多啦…', '囤点别的嘛…', '主食超标了哦…'],
      'gap_oil': ['有点腻腻的…', '油油的难受…', '想喝点水…', '清淡一点嘛…'],
      'no_record': ['今天吃了什么呀', '饿饿…囤不到货', '记录一下嘛…', '今天还没开饭？'],
      'morning': ['早上好呀…', '早餐吃了吗…', '新的一天呢～', '早安，伸个懒腰'],
      'midday': ['中午吃点好的…', '午餐时间到啦～', '中午吃什么呀', '干饭干饭～'],
      'afternoon': ['下午吃点水果', '囤点下午茶～', '困了…眯一会', '下午别饿肚子'],
      'evening': ['晚上想吃啥呢…', '晚餐要吃蔬菜哦', '晚上别吃太油…', '晚餐时间到啦～'],
      'night': ['晚安，做个好梦', '早点休息呀～', '困了…晚安…', '明天也要好好吃饭'],
    },
  },
};
