import { deleteMemoWithPassword } from "@/lib/handlers";

export const runtime = "nodejs";

export async function POST(request: Request) {
  return deleteMemoWithPassword(request);
}
