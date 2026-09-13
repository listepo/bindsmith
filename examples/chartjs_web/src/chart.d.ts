/** A Chart.js chart instance (subset of chart.js 4.x). */
export declare class Chart {
  constructor(item: CanvasRenderingContext2D, config: ChartConfiguration);
  /** Updates the chart after data changes. */
  update(): void;
  /** Destroys the chart. */
  destroy(): void;
  readonly id: string;
}

/** Options for constructing a Chart. */
export interface ChartConfiguration {
  type: string;
  data: ChartData;
}

export interface ChartData {
  labels?: string[];
  datasets: ChartDataset[];
}

export interface ChartDataset {
  label?: string;
  data: number[];
}
