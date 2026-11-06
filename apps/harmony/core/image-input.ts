import { sessionImageLimits, validatePromptImages } from '../../android/src/screens/chat-images'
import { imagePreviewMetadata } from '../../android/src/services/image-preview-metadata'
import type { RemoteSession, ImageMediaType } from '../../android/src/types'

export function imageInputLimits(session?: RemoteSession) {
  const limits = session && sessionImageLimits(session)
  return { imageAllowed: !!session && (!!limits || ['codex','cursor','antigravity'].includes(session.backend ?? 'harness')),
    imageMaxCount: Math.min(16, limits?.maxImagesPerMessage ?? 4),
    imageMaxBytes: Math.min(8*1024*1024, limits?.maxImageBytes ?? 8*1024*1024) }
}
export function validateImageInput(session: RemoteSession, images: Array<{ data: string; mediaType: string }>): void {
  if (!images.length) return
  const input = imageInputLimits(session)
  if (!input.imageAllowed) throw new Error('此后端没有发布图片支持。')
  if (images.length > input.imageMaxCount) throw new Error('图片数量超过主机限制。')
  let total = 0
  const prepared = images.map(image => {
    if (!image.data || image.data.length > Math.ceil(input.imageMaxBytes/3)*4 || !/^[A-Za-z0-9+/]+={0,2}$/.test(image.data)) throw new Error('图片格式或大小超过主机限制。')
    const bytes = Uint8Array.from(atob(image.data), char => char.charCodeAt(0))
    total += bytes.byteLength
    if (bytes.byteLength > input.imageMaxBytes || total > 32*1024*1024) throw new Error('图片总大小超过主机或本机内存限制。')
    const metadata = imagePreviewMetadata(bytes)
    if (!metadata.ok || metadata.mimeType !== image.mediaType) throw new Error('图片格式、尺寸或像素超过限制。')
    return { ...image, mediaType: metadata.mimeType as ImageMediaType, uri: '', bytes: bytes.byteLength, width: metadata.width, height: metadata.height }
  })
  const error = validatePromptImages(prepared, sessionImageLimits(session))
  if (error) throw new Error(error)
}
