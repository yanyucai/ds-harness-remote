export const files = new Map<string, { data: Uint8Array; mtime: number }>()
export const handles = new Map<number, string>()
let next = 1
export default {
  OpenMode: { READ_ONLY: 0 },
  async open(uri: string) { if (!files.has(uri)) throw new Error('Missing fixture'); const fd=next++; handles.set(fd,uri); return {fd} },
  async stat(fd: number) { const f=files.get(handles.get(fd)!); if(!f)throw new Error('Closed file');return {size:f.data.byteLength,mtime:f.mtime} },
  async read(fd: number, target: ArrayBuffer, options: {offset:number;length:number}) { const f=files.get(handles.get(fd)!)!;const b=f.data.subarray(options.offset,options.offset+options.length);new Uint8Array(target).set(b);return b.length },
  async close(fd: number) { handles.delete(fd) },
}
