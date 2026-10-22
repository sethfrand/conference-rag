import { authenticateRequest } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";

const OPENAI_EMBEDDINGS_URL = "https://api.openai.com/v1/embeddings";
const MAX_QUESTION_LENGTH = 8_000;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const auth = await authenticateRequest(request);
    if (auth.error) {
      return jsonResponse({ error: auth.error }, 401);
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return jsonResponse({ error: "Request body must be valid JSON" }, 400);
    }

    const question =
      typeof body === "object" && body !== null && "question" in body
        ? (body as { question?: unknown }).question
        : undefined;

    if (typeof question !== "string" || question.trim().length === 0) {
      return jsonResponse({ error: "question must be a non-empty string" }, 400);
    }

    const normalizedQuestion = question.trim();
    if (normalizedQuestion.length > MAX_QUESTION_LENGTH) {
      return jsonResponse(
        { error: `question must be ${MAX_QUESTION_LENGTH} characters or fewer` },
        400,
      );
    }

    const openAiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openAiApiKey) {
      console.error("OPENAI_API_KEY is not configured");
      return jsonResponse({ error: "Embedding service is unavailable" }, 500);
    }

    const openAiResponse = await fetch(OPENAI_EMBEDDINGS_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAiApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "text-embedding-3-small",
        input: normalizedQuestion,
        encoding_format: "float",
      }),
    });

    if (!openAiResponse.ok) {
      const errorText = await openAiResponse.text();
      console.error(
        `OpenAI embeddings request failed (${openAiResponse.status}): ${errorText}`,
      );
      return jsonResponse({ error: "Failed to generate embedding" }, 502);
    }

    const result = await openAiResponse.json();
    const embedding = result?.data?.[0]?.embedding;

    if (!Array.isArray(embedding)) {
      console.error("OpenAI returned an invalid embeddings response");
      return jsonResponse({ error: "Embedding service returned invalid data" }, 502);
    }

    return jsonResponse({ embedding });
  } catch (error) {
    console.error("Unexpected embed-question error", error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
