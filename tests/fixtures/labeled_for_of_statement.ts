const fileKeys = ['avatar', 'document'];

checkFile: for (const fileFieldKey of fileKeys) {
  if (fileFieldKey === 'avatar') {
    break checkFile;
  }
}
