import * as crypto from 'crypto';

export class PasswordJsonCryptoUtil {
  private readonly algorithm = 'aes-256-gcm';
  private readonly keyLength = 32; // 256 bits
  private readonly saltLength = 16; // 128 bits
  private readonly ivLength = 12; // 96 bits for GCM
  private readonly tagLength = 16; // 128 bits
  private readonly pbkdf2Iterations = 100000; // Number of iterations for PBKDF2

  private deriveKey(password: string, salt: Buffer): Buffer {
    return crypto.pbkdf2Sync(password, salt, this.pbkdf2Iterations, this.keyLength, 'sha256');
  }

  encrypt(data: any, password: string): string {
    // Convert data to JSON string
    const jsonString = JSON.stringify(data);

    // Generate a random salt and IV
    const salt = crypto.randomBytes(this.saltLength);
    const iv = crypto.randomBytes(this.ivLength);

    // Derive a key from the password and salt
    const key = this.deriveKey(password, salt);

    // Create cipher
    const cipher = crypto.createCipheriv(this.algorithm, key, iv, { authTagLength: this.tagLength });

    // Encrypt the data
    let encrypted = cipher.update(jsonString, 'utf8', 'hex');
    encrypted += cipher.final('hex');

    // Get the authentication tag
    const tag = cipher.getAuthTag();

    // Combine all pieces: salt (16 bytes) + iv (12 bytes) + tag (16 bytes) + encrypted data
    return Buffer.concat([salt, iv, tag, Buffer.from(encrypted, 'hex')]).toString('base64');
  }

  decrypt(encryptedData: string, password: string): any {
    // Convert the base64 string back to a buffer
    const data = Buffer.from(encryptedData, 'base64');

    // Extract the pieces
    const salt = data.subarray(0, this.saltLength);
    const iv = data.subarray(this.saltLength, this.saltLength + this.ivLength);
    const tag = data.subarray(this.saltLength + this.ivLength, this.saltLength + this.ivLength + this.tagLength);
    const encrypted = data.subarray(this.saltLength + this.ivLength + this.tagLength);

    // Derive the key
    const key = this.deriveKey(password, salt);

    // Create decipher
    const decipher = crypto.createDecipheriv(this.algorithm, key, iv, { authTagLength: this.tagLength });
    decipher.setAuthTag(tag);

    try {
      // Decrypt the data
      let decrypted = decipher.update(encrypted.toString('hex'), 'hex', 'utf8');
      decrypted += decipher.final('utf8');

      // Parse the JSON string
      return JSON.parse(decrypted);
    } catch (error) {
      throw new Error('Decryption failed. This could be due to an incorrect password or corrupted data.');
    }
  }
}