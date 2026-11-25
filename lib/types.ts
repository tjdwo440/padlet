export type Memo = {
  id: string;
  title: string;
  content: string;
  color: string;
  position: number | null;
  created_at: string;
  updated_at?: string | null;
};

export type ToastMessage = {
  id: number;
  message: string;
  tone: "success" | "error" | "info";
};
