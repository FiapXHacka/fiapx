# ADR-0018: Regras e limites do processamento de vídeo

- **Status:** Proposto
- **Data:** 2026-11-23
- **Decisores:** time FIAP X
- **Requisitos relacionados:** RF-01, RF-05

## Contexto

O projeto base roda `ffmpeg -i <video> -vf fps=1 frame_%04d.png` e compacta os PNGs. Isso precisa ser mantido
(é o produto que os investidores viram), mas sem limites um único vídeo grande esgota o disco do pod ou estoura o
`consumer_timeout` do RabbitMQ. Estimativa: 1 frame PNG 1080p ≈ 2–3 MB, então um vídeo de 10 min gera ~600 frames ≈ 1,5 GB.

## Decisão

| Regra | Valor inicial (configurável por env) |
|---|---|
| Formatos aceitos | `mp4`, `avi`, `mov`, `mkv`, validados pela **extensão na criação** e pelo **`ffprobe` no worker** (o conteúdo manda, não o nome) |
| Tamanho máximo | 500 MB (`MAX_VIDEO_SIZE_BYTES`) |
| Duração máxima | 10 min (`MAX_VIDEO_DURATION_SECONDS`), checada com `ffprobe` antes de extrair |
| Taxa de extração | 1 frame/s (`FRAMES_PER_SECOND`), igual ao base |
| Formato do frame | PNG (igual ao base) |
| Timeout do ffmpeg | 15 min (`context.WithTimeout`); depois disso, `PROCESSING_TIMEOUT` |
| Diretório de trabalho | `emptyDir` por vídeo (`/work/{videoId}`), apagado sempre com `defer`, inclusive em erro |
| Saída | `frames.zip` com streaming para o S3 (multipart), metadados `frame-count` e `source-duration` |

### Classificação de erros (`errorCode`)

| Código | Tipo | Ação |
|---|---|---|
| `INVALID_VIDEO` | permanente | ack + `video.processing-failed` (o `ffprobe` não reconhece o arquivo) |
| `VIDEO_TOO_LONG` / `VIDEO_TOO_LARGE` | permanente | ack + failed |
| `NO_FRAMES_EXTRACTED` | permanente | ack + failed |
| `STORAGE_UNAVAILABLE`, `BROKER_UNAVAILABLE` | transitório | retry em processo (1 s, 4 s, 16 s); se esgotar, `reject(requeue=false)` → DLQ → `MAX_ATTEMPTS_EXCEEDED` |
| `PROCESSING_TIMEOUT` | permanente | ack + `video.processing-failed` (reprocessar o mesmo vídeo estouraria de novo) |
| `MAX_ATTEMPTS_EXCEEDED` | final | publicado pelo consumidor da DLQ |

Erro permanente **não** volta para a fila: reprocessar não muda o resultado e só gasta CPU.

## Consequências

**Positivas**
- Custo previsível por vídeo, o que permite dimensionar os pods ([ADR-0014](0014-escalabilidade-hpa-keda.md)).
- O usuário recebe um motivo claro no e-mail e na listagem.

**Negativas / riscos**
- Vídeos acima dos limites são recusados. Para aceitá-los, seria preciso dividir o processamento em segmentos (evolução).
