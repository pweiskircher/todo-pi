import { Type } from "@sinclair/typebox";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import net from "node:net";

type BridgeResponse = {
  isSuccess: boolean;
  payload?: unknown;
  errorCode?: string;
  message?: string;
};

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

  return await new Promise<BridgeResponse>((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    let buffer = "";

    socket.on("connect", () => {
      socket.write(payload);
    });

    socket.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      const newlineIndex = buffer.indexOf("\n");
      if (newlineIndex === -1) return;

      const line = buffer.slice(0, newlineIndex).replace(/\r$/, "");
      socket.end();

      try {
        resolve(JSON.parse(line) as BridgeResponse);
      } catch (error) {
        reject(error);
      }
    });

    socket.on("error", (error) => {
      reject(error);
    });

    socket.on("end", () => {
      if (buffer.length === 0) {
        reject(new Error("Bridge closed connection without a response"));
      }
    });
  });
}

function resultText(payload: unknown): string {
  if (payload === undefined || payload === null) return "OK";
  if (typeof payload === "string") return payload;
  return JSON.stringify(payload, null, 2);
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
      const response = await callBridge(options.name, (params ?? {}) as Record<string, unknown>);
      if (!response.isSuccess) {
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
