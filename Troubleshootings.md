Troubleshootings

1. Verificar la existencia de los directorios de backup
```bash
ls -ld /fileser/sftpd/med/ftpemm/tobss/rat_cdr/voice/backup/20260320
ls -ld /fileser/sftpd/med/ftpemm/tobss/rat_cdr/voice/backup/20260321
ls -ld /fileser/sftpd/med/ftpemm/tobss/rat_cdr/voice/backup/20260322
```

2. Verificar si hay archivos que coincidan con el patrón TTFILE-GSM*
```bash
find /fileser/sftpd/med/ftpemm/tobss/rat_cdr/voice/backup/20260320 -maxdepth 1 -type f -name 'TTFILE-GSM*' | head -5
```

3. Inspeccionar una línea de un archivo real (si existe)
```bash
archivo=$(find /fileser/sftpd/med/ftpemm/tobss/rat_cdr/voice/backup/20260320 -maxdepth 1 -type f -name 'TTFILE-GSM*' | head -1)
if [ -n "$archivo" ]; then
    cat "$archivo" 2>/dev/null | head -n 1
fi
```

4. Probar el conteo manualmente para un directorio específico
# Por ejemplo, para el directorio 20260320 y fecha 20260320
```bash
find /fileser/sftpd/med/ftpemm/tobss/rat_cdr/voice/backup/20260320 -maxdepth 1 -type f -name 'TTFILE-GSM*' -print0 | \
xargs -0 -r cat 2>/dev/null | awk -F'|' '$9 == "20260320" {c++} END {print c+0}'
```