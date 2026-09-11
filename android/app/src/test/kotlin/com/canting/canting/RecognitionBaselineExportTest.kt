package com.canting.canting

import java.io.File
import java.util.Base64
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Explicit offline benchmark entry point; no production dependencies or phone access. */
class RecognitionBaselineExportTest {
    @Test fun exportCurrentParser() {
        val folder = System.getenv("CANTING_BENCHMARK_DIR")
        assumeTrue("Run through tools/recognition_benchmark/run.ps1", folder != null)
        val root = File(folder!!)
        val linesByCase = linkedMapOf<String, MutableList<OcrLine>>()
        File(root, "input.tsv").forEachLine { row ->
            val fields = row.split('\t')
            val id = fields[0]
            val lines = linesByCase.getOrPut(id) { mutableListOf() }
            if (fields.size > 1) {
                require(fields.size == 6) { "Malformed input row for $id" }
                lines.add(OcrLine(String(Base64.getDecoder().decode(fields[5]), Charsets.UTF_8),
                    fields[1].toIntOrNull(), fields[2].toIntOrNull(),
                    fields[3].toIntOrNull(), fields[4].toIntOrNull()))
            }
        }
        assertTrue("Benchmark must include cases", linesByCase.isNotEmpty())
        File(root, "actual.tsv").bufferedWriter().use { out ->
            linesByCase.forEach { (id, lines) ->
                val result = ScreenshotDishParser.extract(lines)
                out.appendLine(id)
                result.dishes.forEach { dish ->
                    val name = Base64.getEncoder().encodeToString(dish.name.toByteArray(Charsets.UTF_8))
                    out.appendLine("$id\t$name\t${dish.quantity}\t${dish.requiresConfirmation}")
                }
            }
        }
    }
}
