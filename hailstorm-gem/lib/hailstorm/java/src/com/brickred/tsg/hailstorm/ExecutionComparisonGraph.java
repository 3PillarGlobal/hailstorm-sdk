package com.brickred.tsg.hailstorm;

import java.awt.Color;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;

import org.jfree.chart.ChartUtilities;
import org.jfree.chart.JFreeChart;
import org.jfree.chart.axis.CategoryAxis;
import org.jfree.chart.axis.NumberAxis;
import org.jfree.chart.plot.CategoryPlot;
import org.jfree.chart.plot.CombinedDomainCategoryPlot;
import org.jfree.chart.renderer.category.LineAndShapeRenderer;
import org.jfree.data.category.DefaultCategoryDataset;

public class ExecutionComparisonGraph {

	private static final String responseRangeLabel = "Response Time (ms)";

	private static final String throughputRangeLabel = "Transactions/second";

	private static final String categoryKey = "Virtual Users";

	private final String graphFilePath;

	private CategoryPlot responsePlot;

	private CategoryPlot throughputPlot;

	public ExecutionComparisonGraph(String graphFilePath) {
		this.graphFilePath = graphFilePath;
	}

	public void addResponseTimeDataItem(String domainLabel, double responseTime) {

		((DefaultCategoryDataset) getResponsePlot().getDataset()).addValue(
				responseTime, responseRangeLabel, domainLabel);
	}

	public void addThroughputDataItem(String domainLabel, double throughput) {

		((DefaultCategoryDataset) getThroughputPlot().getDataset()).addValue(
				throughput, throughputRangeLabel, domainLabel);
	}

	public ChartModel build(int width, int height) throws IOException {

		CombinedDomainCategoryPlot plot = new CombinedDomainCategoryPlot(
				new CategoryAxis(categoryKey));

		plot.add(getResponsePlot());
		plot.add(getThroughputPlot());

		JFreeChart chart = new JFreeChart(plot);
		chart.setBackgroundPaint(Color.white);

		String outFilePath = String.format("%s.png", graphFilePath);
		OutputStream outStream = new FileOutputStream(outFilePath);
		ChartUtilities.writeChartAsPNG(outStream, chart, width, height);
		outStream.close();

		return new ChartModel(outFilePath, width, height);
	}

	private CategoryPlot getResponsePlot() {

		if (responsePlot == null) {
			NumberAxis rangeAxis = new NumberAxis(responseRangeLabel);
			rangeAxis.setAutoRangeIncludesZero(false);

			responsePlot = new CategoryPlot(new DefaultCategoryDataset(), null,
					rangeAxis, new LineAndShapeRenderer(true, true));

			responsePlot.setDomainGridlinesVisible(true);
		}

		return responsePlot;
	}

	private CategoryPlot getThroughputPlot() {

		if (throughputPlot == null) {
			NumberAxis rangeAxis = new NumberAxis(throughputRangeLabel);
			rangeAxis.setAutoRangeIncludesZero(false);

			throughputPlot = new CategoryPlot(new DefaultCategoryDataset(),
					null, rangeAxis, new LineAndShapeRenderer(true, true));

			throughputPlot.setDomainGridlinesVisible(true);
		}

		return throughputPlot;
	}
}
