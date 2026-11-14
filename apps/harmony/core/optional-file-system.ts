// Android's optional reader is never used by the Harmony picker path: native files
// are supplied through uploadFileReaderToWorkspace and NetworkKit/ArkTS owns I/O.
export const FileMode = undefined
export const File = undefined
export const EncodingType = { Base64: 'base64' }
export async function readAsStringAsync(): Promise<string> { throw new Error('Use the native bounded file reader.') }
