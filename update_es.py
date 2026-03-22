#!/usr/bin/env python3
import re

def parse_strings_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    entries = {}
    pattern = r'^"([^"]+)"\s*=\s*"([^"]*(?:\\.[^"]*)*)";'
    for match in re.finditer(pattern, content, re.MULTILINE):
        key, value = match.groups()
        entries[key] = value
    return entries

def write_strings_file(path, entries):
    with open(path, 'w', encoding='utf-8') as f:
        for key in sorted(entries.keys()):
            value = entries[key]
            f.write(f'"{key}" = "{value}";\n')

base_dir = "StreetStamps"
en = parse_strings_file(f"{base_dir}/en.lproj/Localizable.strings")
zh = parse_strings_file(f"{base_dir}/zh-Hans.lproj/Localizable.strings")

# 西班牙语翻译映射（基于英文->西班牙语）
es_translations = {
    "account_center_title": "Centro de Cuenta",
    "account_display_name_label": "Nombre para mostrar",
    "account_edit_exclusive_id": "Editar ID Exclusivo",
    "account_email_label": "Correo electrónico",
    "account_exclusive_id_change_once": "El ID Exclusivo solo se puede cambiar una vez. Por favor, elige con cuidado.",
    "account_exclusive_id_empty": "El ID Exclusivo no puede estar vacío",
    "account_exclusive_id_label": "ID Exclusivo",
    "account_exclusive_id_locked": "El ID Exclusivo ya se ha cambiado una vez y no se puede cambiar de nuevo.",
    "account_exclusive_id_placeholder": "ID Exclusivo (letras/números/guiones bajos)",
    "account_exclusive_id_rules": "El ID Exclusivo solo admite letras, números y guiones bajos",
    "account_exclusive_id_updated": "ID Exclusivo actualizado",
    "account_fetch_profile_failed_format": "Error al cargar el perfil: %@",
    "account_id_format": "ID: %@",
    "account_login": "INICIAR SESIÓN",
    "account_register": "REGISTRARSE",
    "account_save_display_name": "Guardar Nombre",
    "account_save_exclusive_id": "Guardar ID Exclusivo",
    "account_section_account": "CUENTA",
    "account_section_actions": "ACCIONES DE CUENTA",
    "account_section_developer": "DESARROLLADOR",
    "account_section_visibility": "VISIBILIDAD DEL PERFIL",
    "all_time": "Todo el tiempo",
    "app_name": "Worldo",
    "apply": "Aplicar",
    "auth_create_account": "CREAR CUENTA",
    "auth_create_account_subtitle": "Crea tu cuenta de aventura",
    "auth_email": "CORREO ELECTRÓNICO",
    "auth_fill_email_password": "Por favor ingresa correo y contraseña",
    "auth_forgot_password": "¿Olvidaste tu contraseña?",
    "auth_forgot_password_hint": "Por favor usa la acción de cambiar contraseña en Configuración.",
    "auth_full_name": "NOMBRE COMPLETO",
    "auth_have_account": "¿Ya tienes una cuenta?",
    "auth_no_account": "¿No tienes una cuenta?",
    "auth_password": "CONTRASEÑA",
    "auth_password_mismatch": "Las contraseñas no coinciden",
    "auth_remembered_password": "¿Recordaste tu contraseña?",
    "auth_sign_in": "INICIAR SESIÓN",
    "auth_sign_in_lower": "Iniciar sesión",
    "auth_sign_in_subtitle": "Ingresa tus credenciales para continuar",
    "auth_sign_up": "REGISTRARSE",
    "backend_base_url_placeholder": "API_BASE_URL (por ejemplo https://api.example.com)",
    "backend_configuration": "Configuración del Backend",
    "backend_current_url_format": "URL actual: %@",
    "backend_url_saved": "URL del backend guardada",
    "cities_title": "Ciudades",
    "clear": "Limpiar",
    "collection_segment_cities": "Ciudades",
    "collection_segment_journeys": "Viajes",
    "collection_title": "Mi Worldo",
    "coming_soon_message": "%@ aún no está disponible.",
    "content_unavailable": "El contenido no está disponible o ya no existe",
    "continue_as_guest": "Continuar como Invitado",
    "date_range": "Rango de Fechas",
    "debug_cn_test_full": "Módulo de prueba de China",
    "debug_cn_test_section": "Prueba de China",
    "debug_tools_title": "Herramientas de Depuración",
    "delete_journey_confirm_title": "¿Eliminar este viaje?",
    "details_unavailable_message": "Solo las miniaturas públicas están disponibles para las tarjetas de ciudad de este amigo en este momento.",
    "details_unavailable_title": "Detalles no disponibles",
    "discard": "Descartar",
    "discard_changes_title": "¿Descartar cambios?",
    "discard_edit_message": "Los cambios actuales no se guardarán.",
    "discard_journey": "Descartar Viaje",
    "discard_journey_title": "¿Descartar viaje?",
    "done": "Hecho",
    "email_still_unverified": "Este correo aún no está verificado.",
    "ep_format": "%@ EP",
    "equipment_apply_try_on": "Aplicar Prueba",
    "equipment_buy_all_and_apply": "Comprar todo y aplicar",
    "equipment_coins_added_format": "+%d monedas",
    "equipment_equipped_feedback": "Equipado",
    "equipment_purchase_confirm_message": "%@\nPrecio: %d monedas\nSaldo: %d -> %d",
    "equipment_purchased_and_applied": "Comprado y aplicado",
    "equipment_suit": "Traje",
    "equipment_title_upper": "EQUIPO",
    "equipment_total_price_format": "Total %d",
    "equipment_try_on_mode": "Modo de Prueba",
    "equipment_trying_on": "Probando",
    "equipment_under": "Inferior",
    "equipment_unlock_prompt": "¿Desbloquear este artículo?",
    "equipment_unlocked_and_equipped": "Desbloqueado y equipado",
    "equipment_unowned_items": "Artículos No Poseídos",
    "equipment_upper": "Superior",
    "explore": "EXPLORAR",
    "explorer_fallback": "USUARIO",
    "finish_upper": "FINALIZAR",
    "friend_journey_detail_title": "Viaje",
    "friend_profile_cta_done": "Sentado",
    "friend_profile_cta_idle": "Tomar asiento",
    "friend_profile_cta_loading": "Sentándose...",
    "friend_profile_stomp_failed_format": "No se pudo sentar: %@",
    "friend_profile_stomp_success_format": "Te sentaste en el sofá de %@",
    "friends_accept": "Aceptar",
    "friends_accept_failed_format": "Error al aceptar: %@",
    "friends_active_ago": "Activo hace %@",
    "friends_add_failed": "Error al agregar amigo: %@",
    "friends_add_method_handle": "Identificador",
    "friends_add_method_invite": "Código de Invitación",
    "friends_add_method_picker": "Método",
    "friends_add_method_qr": "Código QR",
    "friends_add_note_optional": "Nota de amigo (opcional)",
    "friends_add_submit": "Agregar Amigo",
    "friends_add_submitting": "Agregando...",
    "friends_add_title": "Agregar Amigo",
    "friends_ago_days_format": "hace %dd",
    "friends_ago_hours_format": "hace %dh",
    "friends_ago_minutes_format": "hace %dm",
    "friends_ago_weeks_format": "hace %ds",
    "friends_backend_not_configured": "La URL del backend no está configurada. Configura API_BASE_URL en el Centro de Cuenta primero.",
    "friends_badge_city": "CIUDAD",
    "friends_badge_journey": "VIAJE",
    "friends_badge_memory": "MEMORIA",
    "friends_delete_confirm_message": "Serán eliminados de tu lista de amigos y deberán enviar una nueva solicitud para reconectar.",
    "friends_delete_confirm_title": "¿Eliminar este amigo?",
    "friends_delete_failed": "Error al eliminar",
    "friends_delete_friend": "Eliminar Amigo",
    "friends_distance_compact_format": "%.1fkm",
    "friends_empty_activity": "Aún no hay actividad de amigos",
    "friends_empty_all": "Aún no hay amigos, toca + para agregar",
    "friends_event_added_memories": "Agregó %d nuevas memorias",
    "friends_event_completed": "Completó %@",
    "friends_event_completed_journey": "Completó un viaje",
    "friends_event_visited": "Visitó %@",
    "friends_exclusive_id_format": "ID Exclusivo: %@",
    "friends_go_login": "Iniciar Sesión",
    "friends_ignore": "Ignorar",
    "friends_joined_format": "Se unió %@",
    "friends_journey_title": "Viaje del Amigo",
    "friends_logged_out_message": "El feed de actividad, la lista de amigos y las solicitudes de amistad solo están disponibles para cuentas con sesión iniciada.",
    "friends_logged_out_title": "Inicia sesión para ver la actividad de amigos",
    "friends_mark_all_read": "Marcar Todo como Leído",
    "friends_photos_count_format": "%d fotos",
    "friends_postcard_prompt": "te trae una postal",
    "friends_recent_journey_ago": "Viaje reciente hace %@",
    "friends_reject_failed_format": "Error al ignorar: %@",
    "friends_request_accepted": "Solicitud de amistad aceptada",
    "friends_request_rejected": "Solicitud de amistad rechazada",
    "friends_tab_activity": "FEED DE ACTIVIDAD",
    "friends_tab_all": "TODOS LOS AMIGOS",
    "friends_title": "AMIGOS",
    "friends_waiting_approval": "Esperando aprobación",
    "friends_welcome": "¡Bienvenido!",
}

# 读取现有西班牙语翻译
es_existing = parse_strings_file(f"{base_dir}/es.lproj/Localizable.strings")

# 合并：使用新翻译更新
es_final = {}
for key in en.keys():
    if key in es_translations:
        es_final[key] = es_translations[key]
    elif key in es_existing:
        es_final[key] = es_existing[key]
    else:
        es_final[key] = en[key]  # 使用英文作为后备

write_strings_file(f"{base_dir}/es.lproj/Localizable.strings", es_final)
print(f"✓ 西班牙语已更新: {len(es_final)} 个键")
print(f"  - 新翻译: {len(es_translations)} 个")
print(f"  - 保留原有: {len(es_existing)} 个")
