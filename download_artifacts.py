import os
import zipfile
import io
from pathlib import Path
import requests
from dotenv import load_dotenv

REPO_OWNER = "fernando-aguilar-coro"
REPO_NAME = "vulcan-circuit"
ARTIFACT_NAME = "godot-gdextension-windows-template_debug"

def main():
    load_dotenv()
    token = os.getenv("TOKEN")
    if not token:
        print("Error: No se encontró la variable TOKEN en el entorno o archivo .env")
        return

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
    }

    print("Buscando últimos artefactos en GitHub...")
    url = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/actions/artifacts"
    response = requests.get(url, headers=headers)

    if response.status_code != 200:
        print(f"Error al conectar con GitHub: {response.text}")
        return

    artifacts = response.json().get("artifacts", [])
    target_artifact = next((a for a in artifacts if a["name"] == ARTIFACT_NAME), None)

    if not target_artifact:
        print(f"No se encontró el artefacto '{ARTIFACT_NAME}'.")
        return

    print(f"Descargando {target_artifact['name']}...")
    download_url = target_artifact["archive_download_url"]
    zip_response = requests.get(download_url, headers=headers)

    if zip_response.status_code != 200:
        print(f"Error al descargar: {zip_response.status_code}")
        return

    # Extraer los archivos mapeándolos a project/bin/
    with zipfile.ZipFile(io.BytesIO(zip_response.content)) as zip_ref:
        for member in zip_ref.infolist():
            if member.is_dir():
                continue
            
            target_path = Path("project/bin") / member.filename
            target_path.parent.mkdir(parents=True, exist_ok=True)
            
            with zip_ref.open(member) as source, target_path.open("wb") as target:
                target.write(source.read())
                
    print("¡Listo! Archivos descargados y extraídos correctamente en su sitio (project/bin/).")

if __name__ == "__main__":
    main()


