import { Type } from "@sinclair/typebox";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

type BridgeResponse = {
  isSuccess: boolean;
  payload?: unknown;
  errorCode?: string;
  message?: string;
};

const debugLogPath = path.join(os.tmpdir(), "pi-todo.log");

function debugLog(message: string, details?: unknown) {
  const suffix = details === undefined ? "" : ` ${safeJSONStringify(details)}`;

  try {
    fs.appendFileSync(debugLogPath, `${new Date().toISOString()} [extension] ${message}${suffix}\n`);
  } catch {
    // Best-effort debug logging only.
  }
}

function safeJSONStringify(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function getBridgeConfig() {
  const socketPath = process.env.TODO_PI_SOCKET;
  const token = process.env.TODO_PI_TOKEN;

  if (!socketPath) throw new Error("TODO_PI_SOCKET is not set");
  if (!token) throw new Error("TODO_PI_TOKEN is not set");

  return { socketPath, token };
}

async function callBridge(tool: string, args: Record<string, unknown> = {}): Promise<BridgeResponse> {
  const { socketPath, token } = getBridgeConfig();
  const payload = JSON.stringify({ token, tool, arguments: args }) + "\n";
  debugLog("bridge request", { tool, arguments: args });

  return await new Promise<BridgeResponse>((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    let buffer = "";

    socket.on("connect", () => {
      debugLog("bridge socket connected", { tool, socketPath });
      socket.write(payload);
    });

    socket.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      const newlineIndex = buffer.indexOf("\n");
      if (newlineIndex === -1) return;

      const line = buffer.slice(0, newlineIndex).replace(/\r$/, "");
      socket.end();

      try {
        const response = JSON.parse(line) as BridgeResponse;
        debugLog("bridge response", { tool, response });
        resolve(response);
      } catch (error) {
        debugLog("bridge response parse failed", { tool, line, error: String(error) });
        reject(error);
      }
    });

    socket.on("error", (error) => {
      debugLog("bridge socket error", { tool, error: String(error) });
      reject(error);
    });

    socket.on("end", () => {
      if (buffer.length === 0) {
        const error = new Error("Bridge closed connection without a response");
        debugLog("bridge socket ended without a response", { tool });
        reject(error);
      }
    });
  });
}

function resultText(payload: unknown): string {
  if (payload === undefined || payload === null) return "OK";
  if (typeof payload === "string") return payload;
  return JSON.stringify(payload, null, 2);
}

function normalizeArguments(params: unknown): Record<string, unknown> {
  if (!params || typeof params !== "object" || Array.isArray(params)) {
    debugLog("normalizing non-object tool arguments to empty object", { receivedType: typeof params, value: params ?? null });
    return {};
  }

  const normalized = Object.fromEntries(
    Object.entries(params as Record<string, unknown>).filter(([key, value]) => key.trim().length > 0 && value !== undefined)
  );

  if (Object.keys(normalized).length !== Object.keys(params as Record<string, unknown>).length) {
    debugLog("dropped invalid tool argument keys while normalizing", { original: params, normalized });
  }

  return normalized;
}

function registerBridgeTool(pi: ExtensionAPI, options: {
  name: string;
  label: string;
  description: string;
  parameters: ReturnType<typeof Type.Object>;
}) {
  pi.registerTool({
    name: options.name,
    label: options.label,
    description: options.description,
    parameters: options.parameters,
    async execute(_toolCallId, params) {
      const normalizedArguments = normalizeArguments(params);
      debugLog("executing bridge tool", { tool: options.name, params, normalizedArguments });

      const response = await callBridge(options.name, normalizedArguments);
      if (!response.isSuccess) {
        debugLog("bridge tool failed", { tool: options.name, response });
        throw new Error(`${response.errorCode ?? "bridge_error"}: ${response.message ?? "request failed"}`);
      }

      return {
        content: [{ type: "text", text: resultText(response.payload) }],
        details: response,
      };
    },
  });
}

export default function (pi: ExtensionAPI) {
  registerBridgeTool(pi, {
    name: "getLists",
    label: "Get Lists",
    description: "Get all todo lists from the app.",
    parameters: Type.Object({}),
  });

  registerBridgeTool(pi, {
    name: "getTodos",
    label: "Get Todos",
    description: "Get todos for a specific list.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the todo list" }),
    }),
  });

  registerBridgeTool(pi, {
    name: "createList",
    label: "Create List",
    description: "Create a new todo list.",
    parameters: Type.Object({
      title: Type.String({ description: "Title for the new list" }),
    }),
  });

  registerBridgeTool(pi, {
    name: "createTodo",
    label: "Create Todo",
    description: "Create a todo in a list.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the todo list" }),
      title: Type.String({ description: "Title for the todo" }),
      notes: Type.Optional(Type.String({ description: "Optional notes" })),
    }),
  });

  registerBridgeTool(pi, {
    name: "updateTodo",
    label: "Update Todo",
    description: "Update an existing todo.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the todo list" }),
      todoId: Type.String({ description: "UUID of the todo item" }),
      title: Type.Optional(Type.String({ description: "Updated title" })),
      notes: Type.Optional(Type.String({ description: "Updated notes" })),
    }),
  });

  registerBridgeTool(pi, {
    name: "completeTodo",
    label: "Complete Todo",
    description: "Mark a todo as completed.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the todo list" }),
      todoId: Type.String({ description: "UUID of the todo item" }),
    }),
  });

  registerBridgeTool(pi, {
    name: "moveTodo",
    label: "Move Todo",
    description: "Move a todo within its list.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the todo list" }),
      todoId: Type.String({ description: "UUID of the todo item" }),
      destinationIndex: Type.Number({ description: "Zero-based destination index" }),
    }),
  });
}
