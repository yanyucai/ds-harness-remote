import { describe, expect, it } from 'vitest'
import { imageInputLimits, validateImageInput } from '../core/image-input'
import type { RemoteSession } from '../../android/src/types'
const session = (backend = 'harness', limits?: object) => ({ backend, projections: { values: { imageLimits: limits } } }) as RemoteSession
function png(width = 100, height = 100) {
  const bytes = new Uint8Array(24)
  bytes.set([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0,0,0,0x0d,0x49,0x48,0x44,0x52])
  const view = new DataView(bytes.buffer); view.setUint32(16,width); view.setUint32(20,height)
  return { data: btoa(String.fromCharCode(...bytes)), mediaType: 'image/png' }
}
const limits = { maxImagesPerMessage: 2, maxImageBytes: 1024, maxMessageImageBytes: 1536, maxImagePixels: 40000, maxImageDimension: 200, mediaTypes: ['image/png'] }
describe('Harmony image capability and resource boundaries', () => {
  it('uses validated Host limits and the same explicit backend fallback as Android', () => {
    expect(imageInputLimits(session()).imageAllowed).toBe(false)
    expect(imageInputLimits(session('harness',{maxImageBytes:-1})).imageAllowed).toBe(false)
    expect(imageInputLimits(session('codex')).imageAllowed).toBe(true)
    expect(imageInputLimits(session('harness',limits))).toMatchObject({imageAllowed:true,imageMaxCount:2,imageMaxBytes:1024})
  })
  it('accepts a compatible image and rejects mismatched MIME, count and Host dimensions', () => {
    const host=session('harness',limits)
    expect(()=>validateImageInput(host,[png()])).not.toThrow()
    expect(()=>validateImageInput(host,[{...png(),mediaType:'image/gif'}])).toThrow()
    expect(()=>validateImageInput(host,[png(),png(),png()])).toThrow()
    expect(()=>validateImageInput(host,[png(201,100)])).toThrow()
  })
  it('rejects unadvertised support and decompression bombs before sending any bytes', () => {
    expect(()=>validateImageInput(session(),[png()])).toThrow()
    expect(()=>validateImageInput(session('codex'),[png(100000,100000)])).toThrow()
    expect(()=>validateImageInput(session('codex'),[{data:'YWJj',mediaType:'image/png'}])).toThrow()
  })
})
