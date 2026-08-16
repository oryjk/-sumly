export interface BackendApiResponse<T> {
  code: number;
  message: string;
  data?: T | null;
}
