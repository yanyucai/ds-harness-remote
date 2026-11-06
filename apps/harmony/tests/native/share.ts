class SharedData {
  constructor(public options: { utd?: string; content?: string }) {}
}
class ShareController {
  constructor(public data: SharedData) {}
  async show(_context: unknown, _options: unknown): Promise<void> {}
}
const systemShare = {
  SharedData,
  ShareController,
}
export default systemShare
