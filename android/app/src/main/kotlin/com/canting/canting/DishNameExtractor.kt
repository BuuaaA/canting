package com.canting.canting

data class ExtractedDish(
    val name: String,
    val quantity: Int,
    val requiresConfirmation: Boolean = false,
)

data class DishExtractionResult(
    val merchant: String,
    val dishes: List<ExtractedDish>,
    val warnings: List<String> = emptyList(),
)

object DishNameExtractor {
    private val quantityPattern = Regex("""(?:×|x|X)\s*(\d+)""")
    private val pricePattern = Regex("""[¥￥]\s*\d+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?\s*元""")
    private val purePricePattern = Regex("""^\s*(?:[¥￥]\s*)?\d+(?:\.\d{1,2})?\s*(?:元)?\s*$""")
    private val phonePattern = Regex("""(?:\+?86[- ]?)?1\d{10}|0\d{2,3}[- ]?\d{7,8}""")
    private val timePattern = Regex("""\b(?:[01]?\d|2[0-3]):[0-5]\d\b""")
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

        val units = mutableListOf<ExtractedDish>()
        val warnings = linkedSetOf<String>()
        val specOnly = Regex("""^(?:(?:无糖|不另外加糖|三分糖|正常糖|少糖|半糖|大杯|中杯|小杯|大份|小份|正常份)[\s/、，,（）()]*)+$""")
        var parentIndex: Int? = null
        normalizedLines.forEach { line ->
            if (shouldExclude(line) || cleanMerchant(line) == merchant) {
                parentIndex = null
                return@forEach
            }
            val marker = quantityPattern.find(line)
            val parsed = marker?.groupValues?.get(1)?.toIntOrNull()
            val invalid = marker != null && (parsed == null || parsed !in 1..99)
            if (invalid) warnings.add("数量超出可确认范围，请核对原文并修改数量")
            val cleaned = cleanDishName(line)
            val parent = parentIndex
            if ((specOnly.matches(cleaned) || (cleaned.isEmpty() && marker != null)) && parent != null) {
                val old = units[parent]
                units[parent] = old.copy(
                    name = old.name + (if (invalid) line.replace(whitespacePattern, "") else cleaned),
                    quantity = if (marker != null && !invalid) parsed!! else old.quantity,
                    requiresConfirmation = old.requiresConfirmation || invalid,
                )
                return@forEach
            }
            val name = if (invalid) line.replace(pricePattern, "").replace(whitespacePattern, "") else cleaned
            if (isLikelyDishName(name)) {
                // Text alone cannot establish ownership for add-ons or combo children.
                val ambiguous = line.contains("套餐") || line.startsWith("加料") || line.startsWith("+") || specOnly.matches(cleaned)
                if (ambiguous) warnings.add("套餐或加料归属不确定，请核对并删除重复项")
                units.add(ExtractedDish(name, if (invalid) 1 else parsed ?: 1, invalid || ambiguous))
                parentIndex = units.lastIndex
            } else parentIndex = null
        }
        val merged = linkedMapOf<String, ExtractedDish>()
        units.forEach { dish ->
            val old = merged[dish.name]
            val total = (old?.quantity ?: 0).toLong() + dish.quantity
            if (total > 99) warnings.add("合并数量超出范围，请核对原文并修改数量")
            merged[dish.name] = dish.copy(quantity = if (total > 99) 1 else total.toInt(),
                requiresConfirmation = dish.requiresConfirmation || old?.requiresConfirmation == true || total > 99)
        }
        if (merged.size > MAX_DISH_COUNT) warnings.add("仅处理前20项，请手动补充其余商品")
        // A combo header may duplicate child items: keep every line unresolved.
        val combo = units.any { it.name.contains("套餐") }
        return DishExtractionResult(merchant, merged.values.take(MAX_DISH_COUNT).map {
            if (combo) it.copy(requiresConfirmation = true) else it
        }, warnings.toList())
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
