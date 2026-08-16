export type DialogResult = {
  action: "confirm" | "cancel" | "modal" | "close";
  value?: string | number;
};

export type DialogOptions = {
  title?: string;
  msg?: string;
  showCancelButton?: boolean;
  cancelButtonText?: string;
  confirmButtonText?: string;
  showClose?: boolean;
  actionLayout?: "horizontal" | "vertical";
};

export function useDialog(selector?: string): {
  confirm(options: DialogOptions | string): Promise<DialogResult>;
  close(): void;
};
