import { deleteMemoWithPassword } from "@/lib/handlers";

export const runtime = "nodejs";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  return deleteMemoWithPassword(request, id);
}
