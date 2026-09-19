#!/usr/bin/env python3
"""拉取 Mesh「红利基金」的全仓穿透股息率截面，保存为 JSON。

数据链路：
  1. search_assets        按名称关键词圈定基金 universe（分页，每页 100）
  2. get_factor_metadata  取因子的最新数据日期（snapshot 必须用这个日期，
                          用最新交易日会因因子尚未更新而全部 VALUE_NOT_FOUND）
  3. get_factor_snapshot  分批（每批 100 只）取截面值

鉴权：MESH_API_KEY 环境变量优先，否则从 ZCode MCP 配置读取 betalpha-mesh 的 X-API-Key。

用法：
  python3 tools/mesh_dividend_fund_yield.py
  python3 tools/mesh_dividend_fund_yield.py --keywords 红利,股息 --top 20
  python3 tools/mesh_dividend_fund_yield.py --output data/dividend.json --date 2026-09-02
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

MCP_URL = os.environ.get("MESH_MCP_URL", "http://172.16.60.233:3003/mcp")
ZCODE_CONFIG = os.path.expanduser("~/.zcode/cli/config.json")

FACTOR_CODE = "app_bm_fund_dividend_yield1_po"  # 基金股息率_绝对数_全仓穿透
ASSET_TYPE = "fund"
PAGE_SIZE = 100      # search_assets 单页上限
BATCH_SIZE = 100     # snapshot 单批资产上限
KEYWORDS = ["红利"]  # 可加入 股息/高息 扩大 universe


class MeshMCPClient:
    """极简 MCP streamable-HTTP 客户端，仅实现本次需要的 tools/call。"""

    def __init__(self, url: str, api_key: str, timeout: int = 60):
        self.url = url
        self.api_key = api_key
        self.timeout = timeout
        self.session_id = None
        self._next_id = 1

    def _post(self, payload: dict):
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "X-API-Key": self.api_key,
        }
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        req = urllib.request.Request(
            self.url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST"
        )
        last_err = None
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    sid = resp.headers.get("Mcp-Session-Id")
                    if sid:
                        self.session_id = sid
                    body = resp.read().decode("utf-8")
                    ctype = resp.headers.get("Content-Type", "")
                    if resp.status == 202 or not body.strip():
                        return None
                    if "text/event-stream" in ctype:
                        return self._parse_sse(body)
                    return json.loads(body)
            except urllib.error.HTTPError as e:
                body = e.read().decode("utf-8", "replace")
                last_err = RuntimeError(f"HTTP {e.code}: {body[:500]}")
                if e.code < 500:
                    break  # 4xx 不重试
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                last_err = e
            time.sleep(1.5 * (attempt + 1))
        raise last_err

    @staticmethod
    def _parse_sse(body: str):
        """从 SSE 流里取出 JSON-RPC 响应（取第一个带 id 的 message）。"""
        for line in body.splitlines():
            line = line.strip()
            if line.startswith("data:"):
                data = line[5:].strip()
                if not data:
                    continue
                try:
                    msg = json.loads(data)
                except json.JSONDecodeError:
                    continue
                if isinstance(msg, dict) and ("result" in msg or "error" in msg):
                    return msg
        return None

    def _rpc(self, method: str, params: dict | None = None, notify: bool = False):
        payload = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            payload["params"] = params
        if not notify:
            payload["id"] = self._next_id
            self._next_id += 1
        resp = self._post(payload)
        if notify:
            return None
        if resp is None:
            raise RuntimeError(f"{method}: 空响应")
        if "error" in resp:
            raise RuntimeError(f"{method}: JSON-RPC 错误 {resp['error']}")
        return resp.get("result", {})

    def initialize(self):
        self._rpc(
            "initialize",
            {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "clientInfo": {"name": "mesh-dividend-pull", "version": "1.0"},
            },
        )
        self._rpc("notifications/initialized", notify=True)

    def call_tool(self, name: str, arguments: dict) -> dict:
        result = self._rpc("tools/call", {"name": name, "arguments": arguments})
        if result.get("isError"):
            raise RuntimeError(f"{name}: {result.get('content')}")
        if isinstance(result.get("structuredContent"), dict):
            return result["structuredContent"]
        for block in result.get("content", []):
            if block.get("type") == "text":
                return json.loads(block["text"])
        raise RuntimeError(f"{name}: 无法解析的返回 {str(result)[:300]}")


def resolve_api_key() -> str:
    key = os.environ.get("MESH_API_KEY", "").strip()
    if key:
        return key
    try:
        with open(ZCODE_CONFIG, encoding="utf-8") as f:
            cfg = json.load(f)
        return cfg["mcp"]["servers"]["betalpha-mesh"]["headers"]["X-API-Key"]
    except (OSError, KeyError, json.JSONDecodeError) as e:
        raise SystemExit(
            f"找不到 API Key：请设置环境变量 MESH_API_KEY，或确认 {ZCODE_CONFIG} "
            f"中有 betalpha-mesh 配置（{e}）"
        )


def search_all_funds(client: MeshMCPClient, keywords: list[str]) -> dict:
    """按关键词分页搜索，合并去重。返回 {asset_code: name}。"""
    funds: dict[str, str] = {}
    per_keyword_counts = {}
    for kw in keywords:
        page = 1
        total_pages = 1
        while page <= total_pages:
            resp = client.call_tool(
                "search_assets",
                {"asset_type": ASSET_TYPE, "query": kw, "page": page, "page_size": PAGE_SIZE},
            )
            for item in resp.get("items", []):
                funds.setdefault(item["asset_code"], item.get("name", item["asset_code"]))
            total_count = resp.get("total_count", 0)
            total_pages = resp.get("total_pages", 1)
            per_keyword_counts[kw] = total_count
            if page >= total_pages:
                break
            page += 1
    return funds, per_keyword_counts


def fetch_latest_factor_date(client: MeshMCPClient) -> str:
    meta = client.call_tool("get_factor_metadata", {"code": FACTOR_CODE})
    end_date = meta.get("end_date")
    if not end_date:
        raise SystemExit(f"因子 {FACTOR_CODE} 元数据缺少 end_date：{meta}")
    return end_date


def fetch_snapshot(client: MeshMCPClient, codes: list[str], date: str) -> tuple[dict, list]:
    """分批取截面值。返回 ({code: value}, [{code, reasons}])。"""
    values: dict[str, float] = {}
    missing: list[dict] = []
    for i in range(0, len(codes), BATCH_SIZE):
        batch = codes[i : i + BATCH_SIZE]
        resp = client.call_tool(
            "get_factor_snapshot",
            {"code": FACTOR_CODE, "asset_codes": batch, "date": date},
        )
        for item in resp.get("values", []):
            v = item.get("value")
            if v is not None:
                values[item["asset_code"]] = float(v)
        for item in resp.get("missing", []):
            missing.append({"asset_code": item["asset_code"], "reasons": item.get("reasons", [])})
    return values, missing


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keywords", default=",".join(KEYWORDS), help="逗号分隔的名称关键词")
    parser.add_argument("--date", default=None, help="截面日期 YYYY-MM-DD，默认取因子最新数据日")
    parser.add_argument("--top", type=int, default=10, help="JSON 里单独输出 top N")
    parser.add_argument("--output", default="data/mesh_dividend_fund_yield.json")
    args = parser.parse_args()

    keywords = [k.strip() for k in args.keywords.split(",") if k.strip()]
    if not keywords:
        raise SystemExit("关键词不能为空")

    client = MeshMCPClient(MCP_URL, resolve_api_key())
    print(f"[1/4] 连接 MCP 服务 {MCP_URL} ...")
    client.initialize()

    print(f"[2/4] 按关键词 {keywords} 搜索 {ASSET_TYPE} 资产 ...")
    funds, per_kw = search_all_funds(client, keywords)
    for kw, n in per_kw.items():
        print(f"      关键词「{kw}」命中 {n} 条")
    print(f"      去重后 universe：{len(funds)} 只")

    date = args.date or fetch_latest_factor_date(client)
    print(f"[3/4] 拉取因子 {FACTOR_CODE} 截面（date={date}）...")
    codes = sorted(funds)
    values, missing = fetch_snapshot(client, codes, date)

    ranked = sorted(
        (
            {
                "rank": i + 1,
                "asset_code": code,
                "name": funds[code],
                "dividend_yield": round(v, 6),
                "dividend_yield_pct": round(v * 100, 4),
            }
            for i, (code, v) in enumerate(
                sorted(values.items(), key=lambda kv: kv[1], reverse=True)
            )
        ),
        key=lambda x: x["rank"],
    )
    doc = {
        "factor": {
            "code": FACTOR_CODE,
            "name": "基金股息率_绝对数_全仓穿透",
            "asset_type": ASSET_TYPE,
            "as_of_date": date,
            "unit": "小数（0.05 = 5%）",
        },
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "universe": {
            "keywords": keywords,
            "matched_per_keyword": per_kw,
            "total_matched": len(funds),
            "with_value": len(values),
            "missing": len(missing),
        },
        "top": ranked[: args.top],
        "funds": ranked,
        "missing": missing,
    }

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)

    print(f"[4/4] 已保存 {args.output}")
    print(f"      有值 {len(values)} / 缺失 {len(missing)}，前五：")
    for row in ranked[:5]:
        print(f"      {row['rank']}. {row['name']}（{row['asset_code']}） {row['dividend_yield_pct']}%")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        print(f"执行失败：{e}", file=sys.stderr)
        sys.exit(1)
