import { createMemo, listMemos } from "@/lib/handlers";

export const runtime = "nodejs";

export async function GET() {
  return listMemos();
}

export async function POST(request: Request) {
  return createMemo(request);
}
