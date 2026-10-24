import { AppConfig } from '../../core/common/AppConfig';

export enum Breakpoint {
  /** Phones: one view at a time + bottom navigation. */
  SM = 'sm',
  /** Tablets: sidebar slides over the editor. */
  MD = 'md',
  /** 2-in-1 / PC: docked sidebar and panel, like a desktop IDE. */
  LG = 'lg'
}

/** Window size and breakpoint, updated by EntryAbility. */
@ObservedV2
export class LayoutState {
  @Trace bp: string = Breakpoint.LG;
  @Trace width: number = 0;
  @Trace height: number = 0;

  update(widthVp: number, heightVp: number): void {
    this.width = widthVp;
    this.height = heightVp;
    const next = widthVp < AppConfig.BREAKPOINT_SM_MAX ? Breakpoint.SM :
      (widthVp < AppConfig.BREAKPOINT_MD_MAX ? Breakpoint.MD : Breakpoint.LG);
    if (next !== this.bp) {
      this.bp = next;
    }
  }

  get isPhone(): boolean {
    return this.bp === Breakpoint.SM;
  }

  get isTablet(): boolean {
    return this.bp === Breakpoint.MD;
  }

  get isDesktop(): boolean {
    return this.bp === Breakpoint.LG;
  }
}

export const layoutState: LayoutState = new LayoutState();
