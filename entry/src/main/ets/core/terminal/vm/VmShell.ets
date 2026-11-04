import { EnvironmentDef } from '../../project/Catalog';
import { OutputSink, ShellBackend } from '../ShellBackend';
import { GuestCommands, GuestProject } from './GuestCommands';
import { VmResources, vmRuntime } from './VmRuntime';

/** Terminal backend connected to the app's Linux VM; boots it on first use. */
export class VmShell implements ShellBackend {
  private env: EnvironmentDef;
  private project: GuestProject;
  private resources: VmResources;
  private out: OutputSink;
  private name: string;

  constructor(env: EnvironmentDef, project: GuestProject, resources: VmResources, out: OutputSink, label: string) {
    this.env = env;
    this.project = project;
    this.resources = resources;
    this.out = out;
    this.name = label;
  }

  label(): string {
    return this.name;
  }

  start(cols: number, rows: number): void {
    vmRuntime.attach(this.out, this.project);
    vmRuntime.setWindowSize(cols, rows);
    vmRuntime.start(this.env, this.resources, cols, rows);
  }

  input(data: string): void {
    vmRuntime.write(data);
  }

  resize(cols: number, rows: number): void {
    vmRuntime.setWindowSize(cols, rows);
  }

  /** Runs a command from the project folder once the shell is ready. */
  runLine(line: string): void {
    vmRuntime.run(GuestCommands.inProject(this.project, line));
  }

  /** Disconnects this terminal; the VM keeps running for the next project. */
  stop(): void {
    vmRuntime.detach(this.out);
  }
}
