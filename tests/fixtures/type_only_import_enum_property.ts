export enum ProductGenderEnum {
  MALE = 0,
  FEMALE = 1
}

export class SearchOptionsDto {
  public!: ProductGenderEnum[];
}

const value = ProductGenderEnum.MALE;
