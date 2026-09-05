package com.canting.canting
import org.junit.Test
import java.io.File
import java.util.Base64
class P4ReplayTest {
 @Test fun replayFrozenInputsTwice() {
  val out=File(System.getenv("CANTING_TEST_EVIDENCE_DIR") ?: "build/test-evidence", "parser-actual.tsv")
  out.parentFile?.mkdirs()
  out.writeText("")
  fun emit(id:String, lines:List<String>, repeat:Int) {
   val r=DishNameExtractor.extract(lines)
   out.appendText("$id\t$repeat\t"+r.dishes.joinToString("|") { Base64.getEncoder().encodeToString(it.name.toByteArray(Charsets.UTF_8))+":"+it.quantity+":"+it.requiresConfirmation }+"\n")
  }
  for (repeat in 1..2) {
   emit("unknown",listOf("青青糯山 无糖 小杯 ×1"),repeat)
   emit("typo",listOf("青責糯山"),repeat)
   emit("fees",listOf("配送费 ¥4","包装费 ¥2","优惠 ¥3","实付 ¥30"),repeat)
   emit("spec",listOf("青青糯山","三分糖 大杯","×2"),repeat)
   emit("cake",listOf("奶油蛋糕30寸 ×1","小份巴斯克"),repeat)
   emit("quantity",listOf("米饭×100"),repeat)
   emit("meal",listOf("香辣鸡腿堡","可乐","薯条"),repeat)
   emit("different_specs",listOf("奶茶无糖小杯×1","奶茶正常糖大杯×2"),repeat)
   emit("empty",listOf(),repeat)
   emit("limit",listOf("未知商品1号","未知商品2号","未知商品3号","未知商品4号","未知商品5号","未知商品6号","未知商品7号","未知商品8号","未知商品9号","未知商品10号","未知商品11号","未知商品12号","未知商品13号","未知商品14号","未知商品15号","未知商品16号","未知商品17号","未知商品18号","未知商品19号","未知商品20号","未知商品21号","未知商品22号"),repeat)
  }
 }
}
