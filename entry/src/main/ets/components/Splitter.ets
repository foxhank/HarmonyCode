import { UiConst } from './UiConst';

/** Drag handle between panes. Reports the drag offset from where the drag started. */
@ComponentV2
export struct Splitter {
  /** true: a vertical bar dragged left/right; false: a horizontal bar dragged up/down. */
  @Param vertical: boolean = true;
  @Local dragging: boolean = false;
  @Event onStart: () => void = () => {
  };
  @Event onMove: (offset: number) => void = () => {
  };

  build() {
    Column()
      .width(this.vertical ? $r('app.float.splitter_size') : UiConst.FULL)
      .height(this.vertical ? UiConst.FULL : $r('app.float.splitter_size'))
      .backgroundColor(this.dragging ? $r('app.color.accent') : $r('app.color.border'))
      .gesture(
        PanGesture({ direction: this.vertical ? PanDirection.Horizontal : PanDirection.Vertical })
          .onActionStart(() => {
            this.dragging = true;
            this.onStart();
          })
          .onActionUpdate((e: GestureEvent) => this.onMove(this.vertical ? e.offsetX : e.offsetY))
          .onActionEnd(() => {
            this.dragging = false;
          })
          .onActionCancel(() => {
            this.dragging = false;
          })
      )
  }
}
