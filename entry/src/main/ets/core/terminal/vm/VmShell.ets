import { OutputSink, ShellBackend } from '../ShellBackend';
import { VmBootConfig, VmEngine } from './VmEngine';

/** Terminal backend that forwards everything to a Linux VM's console. */
export class VmShell implements ShellBackend {
  private engine: VmEngine;
  private out: OutputSink;
  private config: VmBootConfig;
  private name: string;

  constructor(engine: VmEngine, out: OutputSink, config: VmBootConfig, label: string) {
    this.engine = engine;
    this.out = out;
    this.config = config;
    this.name = label;
  }

  label(): string {
    return this.name;
  }

  start(cols: number, rows: number): void {
    this.config.cols = cols;
    this.config.rows = rows;
    this.engine.boot(this.config, this.out);
  }

  input(data: string): void {
    this.engine.write(data);
  }

  resize(cols: number, rows: number): void {
    this.engine.resize(cols, rows);
  }

  runLine(line: string): void {
    this.engine.write(line + '\r');
  }

  stop(): void {
    this.engine.shutdown();
  }
}
