# Custom Agents with the Claude Agent SDK

Use the SDK when the agent is a product or pipeline component rather than a helper inside Claude Code.
Docs: [Agent SDK overview](https://platform.claude.com/docs/en/agent-sdk/overview),
[custom tools](https://platform.claude.com/docs/en/agent-sdk/custom-tools),
[system prompts](https://platform.claude.com/docs/en/agent-sdk/modifying-system-prompts). Check them for the
current API before generating code; the SDK evolves quickly.

## System prompt: append or override

| Choice | How (Python) | Result |
| --- | --- | --- |
| Append | `system_prompt={"type": "preset", "preset": "claude_code", "append": "..."}` | Claude Code's behavior plus your rules |
| Override | `system_prompt="You are ..."` | A new product; nothing from Claude Code's prompt remains |
| Default | omit | A minimal prompt with tool instructions only |

The system prompt affects every turn: version it in the repo, keep it focused on the one purpose, and note that
the preset does not load CLAUDE.md unless setting sources are configured.

## Custom tools

Tools are functions with a name, a description the model reads, and an input schema. In Python they are defined
with `@tool` and served from an in-process MCP server:

```python
from typing import Any
from claude_agent_sdk import tool, create_sdk_mcp_server, ClaudeAgentOptions, ClaudeSDKClient

@tool("lookup_order", "Look up an order by id and return its status", {"order_id": str})
async def lookup_order(args: dict[str, Any]) -> dict[str, Any]:
    status = await orders.status(args["order_id"])          # your code
    return {"content": [{"type": "text", "text": f"{args['order_id']}: {status}"}]}

server = create_sdk_mcp_server(name="orders", version="1.0.0", tools=[lookup_order])

options = ClaudeAgentOptions(
    system_prompt="You are the order-support agent. Answer only order status questions.",
    mcp_servers={"orders": server},
    allowed_tools=["mcp__orders__lookup_order"],             # mcp__<server>__<tool>
    max_turns=5,
)

async def main() -> None:
    async with ClaudeSDKClient(options=options) as client:
        await client.query("Where is order A-123?")
        async for message in client.receive_response():
            print(message)
```

Tool design rules: few, well-named tools; descriptions that say when to use them; outputs that are meaningful
text, not raw ids; errors that tell the agent what to do next.

## Structure

Keep every custom agent in the same layout so people and agents can navigate them:

```text
agents/<name>/
  prompts/system.md     # the system prompt, versioned
  tools.py              # custom tools
  main.py               # entry point (query or client loop)
  tests/                # run the agent on fixed inputs, assert on outputs
```

Test agents in isolation with fixed inputs, log every tool call, and only then deploy them.
