import { adminDeleteAll } from "@/lib/handlers";

export const runtime = "nodejs";

export async function POST(request: Request) {
  return adminDeleteAll(request);
}
