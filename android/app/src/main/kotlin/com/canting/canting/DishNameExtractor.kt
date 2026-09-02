package com.canting.canting

data class ExtractedDish(
    val name: String,
    val quantity: Int,
)

data class DishExtractionResult(
    val merchant: String,
    val dishes: List<ExtractedDish>,
)

object DishNameExtractor {
    private val quantityPattern = Regex("""(?:×|x|X)\s*(\d{1,2})""")
    private val pricePattern = Regex("""(?:[¥￥]\s*)?\d+(?:\.\d{1,2})?\s*(?:元)?""")
    private val purePricePattern = Regex("""^\s*(?:[¥￥]\s*)?\d+(?:\.\d{1,2})?\s*(?:元)?\s*$""")
    private val phonePattern = Regex("""(?:\+?86[- ]?)?1\d{10}|0\d{2,3}[- ]?\d{7,8}""")
    private val timePattern = Regex("""\b(?:[01]?\d|2[0-3]):[0-5]\d\b""")
    private val bracketSuffixPattern =
        Regex("""[（(][^）)]*(?:大份|小份|中份|规格|微辣|辣|不辣|加料)[^）)]*[）)]""")
    private val flavorSuffixPattern =
        Regex("""\s*[-—·]\s*(?:微辣|中辣|重辣|不辣|少油|少盐|大份|小份|中份).*$""")
    private val surroundingSymbols = Regex("""^[\s·•●▪■□✓✔★☆_\-—:：]+|[\s·•●▪■□✓✔★☆_\-—:：]+$""")
    private val whitespacePattern = Regex("""\s+""")
    private val meaningfulTextPattern = Regex("""[\p{L}]""")

    private val excludedTerms = listOf(
        "合计",
        "总计",
        "小计",
        "实付",
        "应付",
        "优惠",
        "配送费",
        "打包费",
        "包装费",
        "服务费",
        "餐盒费",
        "订单号",
        "订单时间",
        "下单时间",
        "送达时间",
        "收货地址",
        "配送地址",
        "联系电话",
        "手机号",
        "发票",
    )

    private val merchantTerms = listOf(
        "餐厅",
        "饭店",
        "小馆",
        "食堂",
        "厨房",
        "餐饮",
        "外卖",
        "门店",
        "旗舰店",
    )

    fun extract(lines: List<String>): DishExtractionResult {
        val normalizedLines = lines
            .map(String::trim)
            .filter(String::isNotEmpty)
        val merchant = normalizedLines
            .firstOrNull { line ->
                merchantTerms.any(line::contains) &&
                    excludedTerms.none(line::contains) &&
                    !phonePattern.containsMatchIn(line)
            }
            ?.let(::cleanMerchant)
            .orEmpty()

        val mergedDishes = linkedMapOf<String, Int>()
        normalizedLines.forEach { line ->
            if (shouldExclude(line) || cleanMerchant(line) == merchant) {
                return@forEach
            }
            val quantity = quantityPattern.find(line)
                ?.groupValues
                ?.getOrNull(1)
                ?.toIntOrNull()
                ?.coerceIn(1, 99)
                ?: 1
            val name = cleanDishName(line)
            if (isLikelyDishName(name)) {
                mergedDishes[name] = (mergedDishes[name] ?: 0) + quantity
            }
        }

        return DishExtractionResult(
            merchant = merchant,
            dishes = mergedDishes.entries
                .take(MAX_DISH_COUNT)
                .map { ExtractedDish(name = it.key, quantity = it.value) },
        )
    }

    private fun shouldExclude(line: String): Boolean {
        if (excludedTerms.any(line::contains)) return true
        if (purePricePattern.matches(line)) return true
        if (phonePattern.containsMatchIn(line)) return true
        if (timePattern.containsMatchIn(line) && line.length <= 16) return true
        return false
    }

    private fun cleanDishName(line: String): String {
        return line
            .replace(quantityPattern, "")
            .replace(bracketSuffixPattern, "")
            .replace(flavorSuffixPattern, "")
            .replace(pricePattern, "")
            .replace(surroundingSymbols, "")
            .replace(whitespacePattern, "")
            .trim()
    }

    private fun cleanMerchant(line: String): String {
        return line
            .replace(pricePattern, "")
            .replace(surroundingSymbols, "")
            .replace(whitespacePattern, "")
            .trim()
    }

    private fun isLikelyDishName(name: String): Boolean {
        if (name.length !in 2..30) return false
        if (!meaningfulTextPattern.containsMatchIn(name)) return false
        if (merchantTerms.any(name::contains)) return false
        if (excludedTerms.any(name::contains)) return false
        return true
    }

    private const val MAX_DISH_COUNT = 20
}
