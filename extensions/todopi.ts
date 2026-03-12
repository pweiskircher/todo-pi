import { Type } from "@sinclair/typebox";
import type { ExtensionAPI, ExtensionCommandContext } from "@mariozechner/pi-coding-agent";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

const runtimeInfoPath = path.join(
  os.homedir(),
  "Library",
  "Application Support",
  "TodoPi",
  "bridge-runtime.json"
);

type RuntimeInfo = {
  version: number;
  socketPath: string;
  token: string;
  processIdentifier: number;
  updatedAt: string;
};

type BridgeResponse = {
  isSuccess: boolean;
  payload?: unknown;
  errorCode?: string;
  message?: string;
};

function readRuntimeInfo(): RuntimeInfo {
  if (!fs.existsSync(runtimeInfoPath)) {
    throw new Error(
      `TodoPi bridge info was not found at ${runtimeInfoPath}. Open TodoPi and try again.`
    );
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(fs.readFileSync(runtimeInfoPath, "utf8"));
  } catch (error) {
    throw new Error(`TodoPi bridge info is unreadable: ${String(error)}`);
  }

  if (!parsed || typeof parsed !== "object") {
    throw new Error("TodoPi bridge info is invalid.");
  }

  const info = parsed as Partial<RuntimeInfo>;
  if (typeof info.socketPath !== "string" || info.socketPath.length === 0) {
    throw new Error("TodoPi bridge info is missing socketPath.");
  }
  if (typeof info.token !== "string" || info.token.length === 0) {
    throw new Error("TodoPi bridge info is missing token.");
  }

  return {
    version: typeof info.version === "number" ? info.version : 1,
    socketPath: info.socketPath,
    token: info.token,
    processIdentifier: typeof info.processIdentifier === "number" ? info.processIdentifier : 0,
    updatedAt: typeof info.updatedAt === "string" ? info.updatedAt : new Date(0).toISOString(),
  };
}

async function callBridge(tool: string, args: Record<string, unknown> = {}): Promise<BridgeResponse> {
  const runtimeInfo = readRuntimeInfo();
  const payload = JSON.stringify({
    token: runtimeInfo.token,
    tool,
    arguments: args,
  }) + "\n";

  return await new Promise<BridgeResponse>((resolve, reject) => {
    const socket = net.createConnection(runtimeInfo.socketPath);
    let buffer = "";
    let didResolve = false;

    const fail = (error: Error) => {
      if (didResolve) return;
      didResolve = true;
      socket.destroy();
      reject(error);
    };

    socket.setTimeout(1500, () => {
      fail(new Error("Timed out waiting for TodoPi. Make sure the app is running."));
    });

    socket.on("connect", () => {
      socket.write(payload);
    });

    socket.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      const newlineIndex = buffer.indexOf("\n");
      if (newlineIndex === -1) return;

      const line = buffer.slice(0, newlineIndex).replace(/\r$/, "");
      if (didResolve) return;
      didResolve = true;
      socket.end();

      try {
        resolve(JSON.parse(line) as BridgeResponse);
      } catch (error) {
        reject(new Error(`TodoPi returned malformed JSON: ${String(error)}`));
      }
    });

    socket.on("error", (error) => {
      fail(new Error(`Could not reach TodoPi at ${runtimeInfo.socketPath}. Make sure the app is open. (${String(error)})`));
    });

    socket.on("end", () => {
      if (!didResolve) {
        fail(new Error("TodoPi closed the bridge connection without sending a response."));
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
  bridgeTool: string;
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
      const response = await callBridge(options.bridgeTool, params as Record<string, unknown>);
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

async function notifyStatus(ctx: ExtensionCommandContext) {
  try {
    const runtimeInfo = readRuntimeInfo();
    await callBridge("getLists", {});
    ctx.ui.notify(
      `TodoPi bridge is ready at ${runtimeInfo.socketPath}`,
      "success"
    );
  } catch (error) {
    ctx.ui.notify(String(error), "error");
  }
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("todopi-status", {
    description: "Check whether the TodoPi app bridge is reachable",
    handler: async (_args, ctx) => {
      await notifyStatus(ctx);
    },
  });

  registerBridgeTool(pi, {
    name: "todopi_getLists",
    bridgeTool: "getLists",
    label: "TodoPi Get Lists",
    description: "Get all todo lists from the running TodoPi app.",
    parameters: Type.Object({}),
  });

  registerBridgeTool(pi, {
    name: "todopi_getTodos",
    bridgeTool: "getTodos",
    label: "TodoPi Get Todos",
    description: "Get todos from a TodoPi list by list UUID.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the TodoPi list" }),
    }),
  });

  registerBridgeTool(pi, {
    name: "todopi_createList",
    bridgeTool: "createList",
    label: "TodoPi Create List",
    description: "Create a new list in the running TodoPi app.",
    parameters: Type.Object({
      title: Type.String({ description: "Title for the new TodoPi list" }),
    }),
  });

  registerBridgeTool(pi, {
    name: "todopi_updateListTitle",
    bridgeTool: "updateListTitle",
    label: "TodoPi Rename List",
    description: "Rename an existing TodoPi list.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the TodoPi list" }),
      title: Type.String({ description: "New title for the TodoPi list" }),
    }),
  });

  registerBridgeTool(pi, {
    name: "todopi_deleteList",
    bridgeTool: "deleteList",
    label: "TodoPi Delete List",
    description: "Delete a TodoPi list and all of its todos.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the TodoPi list" }),
    }),
  });

  registerBridgeTool(pi, {
    name: "todopi_createTodo",
    bridgeTool: "createTodo",
    label: "TodoPi Create Todo",
    description: "Create a todo in a TodoPi list.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the TodoPi list" }),
      title: Type.String({ description: "Title for the TodoPi todo" }),
      notes: Type.Optional(Type.String({ description: "Optional notes for the todo" })),
    }),
  });

  registerBridgeTool(pi, {
    name: "todopi_updateTodo",
    bridgeTool: "updateTodo",
    label: "TodoPi Update Todo",
    description: "Update a TodoPi todo title and/or notes.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the TodoPi list" }),
      todoId: Type.String({ description: "UUID of the TodoPi todo" }),
      title: Type.Optional(Type.String({ description: "Updated todo title" })),
      notes: Type.Optional(Type.String({ description: "Updated notes, or an empty string to clear notes" })),
    }),
  });

  registerBridgeTool(pi, {
    name: "todopi_setTodoCompletion",
    bridgeTool: "setTodoCompletion",
    label: "TodoPi Set Todo Completion",
    description: "Mark a TodoPi todo as completed or incomplete.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the TodoPi list" }),
      todoId: Type.String({ description: "UUID of the TodoPi todo" }),
      isCompleted: Type.Boolean({ description: "Whether the todo should be completed" }),
    }),
  });

  registerBridgeTool(pi, {
    name: "todopi_deleteTodo",
    bridgeTool: "deleteTodo",
    label: "TodoPi Delete Todo",
    description: "Delete a TodoPi todo.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the TodoPi list" }),
      todoId: Type.String({ description: "UUID of the TodoPi todo" }),
    }),
  });

  registerBridgeTool(pi, {
    name: "todopi_moveTodo",
    bridgeTool: "moveTodo",
    label: "TodoPi Move Todo",
    description: "Move a TodoPi todo to a new zero-based index within its list.",
    parameters: Type.Object({
      listId: Type.String({ description: "UUID of the TodoPi list" }),
      todoId: Type.String({ description: "UUID of the TodoPi todo" }),
      destinationIndex: Type.Number({ description: "Zero-based destination index" }),
    }),
  });
}
