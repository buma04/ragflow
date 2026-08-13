import json
import os

from common import settings

settings.init_settings()

from api.db.joint_services.tenant_model_service import ensure_paddleocr_from_env
from api.db.services.tenant_model_instance_service import TenantModelInstanceService
from api.db.services.tenant_model_provider_service import TenantModelProviderService
from api.db.services.tenant_model_service import TenantModelService
from api.db.services.user_service import TenantService
from common.constants import LLMType
from common.misc_utils import get_uuid


def ensure_vllm(tenant_id: str) -> str:
    provider = TenantModelProviderService.get_by_tenant_id_and_provider_name(tenant_id, "VLLM")
    if provider is None:
        TenantModelProviderService.insert(id=get_uuid(), tenant_id=tenant_id, provider_name="VLLM")
        provider = TenantModelProviderService.get_by_tenant_id_and_provider_name(tenant_id, "VLLM")

    instance = TenantModelInstanceService.get_by_provider_id_and_instance_name(provider.id, "local-demo")
    extra = json.dumps({"base_url": "http://vllm-qwen:8000/v1"})
    api_key = os.getenv("QWEN_API_KEY", "local-demo-key")
    if instance is None:
        TenantModelInstanceService.insert(
            id=get_uuid(), provider_id=provider.id, instance_name="local-demo", api_key=api_key, extra=extra
        )
        instance = TenantModelInstanceService.get_by_provider_id_and_instance_name(provider.id, "local-demo")
    else:
        TenantModelInstanceService.update_by_id(instance.id, {"api_key": api_key, "extra": extra, "status": "active"})

    model_name = os.getenv("QWEN_SERVED_NAME", "qwen3.5-9b")
    model = TenantModelService.get_by_provider_id_and_instance_id_and_model_type_and_model_name(
        provider.id, instance.id, LLMType.CHAT.value, model_name
    )
    model_extra = json.dumps({"max_tokens": int(os.getenv("VLLM_MAX_MODEL_LEN", "16384")), "is_tools": True})
    if model is None:
        TenantModelService.insert(
            id=get_uuid(), model_name=model_name, provider_id=provider.id,
            instance_id=instance.id, model_type=LLMType.CHAT.value, extra=model_extra
        )
    else:
        TenantModelService.update_by_id(model.id, {"extra": model_extra, "status": "active"})
    return f"{model_name}@local-demo@VLLM"


def main():
    embedding = os.getenv("TEI_MODEL", "BAAI/bge-m3")
    for tenant in TenantService.query():
        chat = ensure_vllm(tenant.id)
        ocr = ensure_paddleocr_from_env(tenant.id)
        updates = {"llm_id": chat, "embd_id": embedding}
        if ocr:
            updates["ocr_id"] = ocr
        TenantService.update_by_id(tenant.id, updates)
        print(f"Configured local demo models for tenant {tenant.id}")


if __name__ == "__main__":
    main()
