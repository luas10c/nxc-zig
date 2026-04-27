function injectable(target: any) { return target; }
function inject(token: string) { return (_: any, __: string, i: number) => {}; }

@injectable
export class UserService {
  constructor(@inject("DB") private db: any) {}

  async find(id: string): Promise<any> {
    return this.db.find(id);
  }
}
