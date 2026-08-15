"""Checks del parseo de bin/jules-cli (sin tocar la red ni la API key)."""
import importlib.machinery
import importlib.util
from pathlib import Path

import pytest

CLI = Path(__file__).resolve().parents[1] / "bin" / "jules-cli"


@pytest.fixture(scope="module")
def jules():
    spec = importlib.util.spec_from_loader("jules_cli", importlib.machinery.SourceFileLoader("jules_cli", str(CLI)))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_describe_agent_message(jules):
    act = {"name": "a/1", "createTime": "t", "originator": "agent",
           "agentMessaged": {"agentMessage": "hola"}}
    assert jules.describe(act) == {"kind": "agentMessaged", "text": "hola", "createTime": "t"}


def test_describe_plan_lists_steps(jules):
    act = {"createTime": "t", "originator": "agent",
           "planGenerated": {"plan": {"steps": [{"title": "uno"}, {"title": "dos"}]}}}
    assert jules.describe(act)["text"] == "1. uno\n2. dos"


def test_describe_unknown_kind_does_not_crash(jules):
    assert jules.describe({"createTime": "t", "somethingNew": {}})["kind"] == "somethingNew"


def test_summarize_outputs_extracts_pr_and_files(jules):
    ses = {"outputs": [
        {"changeSet": {"gitPatch": {"unidiffPatch": "diff\n--- a/x.gd\n+++ b/x.gd\n+linea\n"}}},
        {"pullRequest": {"url": "https://github.com/icarito/Odisea/pull/1", "headRef": "jules-x"}},
    ]}
    summary = jules.summarize_outputs(ses)
    assert summary["pr_url"].endswith("/pull/1")
    assert summary["pr_branch"] == "jules-x"
    assert summary["files"] == ["x.gd"]


def test_api_key_prefers_environment(jules, monkeypatch):
    monkeypatch.setenv("JULES_API_KEY", "clave-de-prueba")
    assert jules.api_key() == "clave-de-prueba"
