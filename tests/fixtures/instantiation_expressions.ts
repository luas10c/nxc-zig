type GetTemplateTuple<T> = T extends string ? [T] : never;
type Message = string;

const printMessage = <ArgTypes extends GetTemplateTuple<Message>>(...args: ArgTypes) => args;

const pipeline = {
  pipeAsync(value: unknown) {
    return value;
  },
};

export const removed = pipeline.pipeAsync(printMessage("Removed :{count} music files.")<[number]>);
