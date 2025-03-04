import { logger } from "@/global";
import TelegramBot from "node-telegram-bot-api";

export class TelegramNotif {
    private subscribers: string[] = [
        // '6820228303',
        '1505578076',
        // '5434736198', // maaza
        '1356705582', // langs
        '1388729514', // hwashere
        '6020162572', //minato
        '985902592'
    ];
    readonly bot: TelegramBot;

    constructor(token: string, shouldPoll: boolean) {
        this.bot = new TelegramBot(token, { polling: shouldPoll });
    }

    // listen to start msgs, register chatId and send registered msg
    activateChatBot() {
        this.bot.on('message', (msg: any) => {
            const chatId = msg.chat.id;
            let text = msg.text.toLowerCase().trim()
            logger.verbose(`Tg: IncomingMsg: ID: ${chatId}, msg: ${text}`)
            if(text=='start') {
                this.bot.sendMessage(chatId, "Registered")
                this.subscribers.push(chatId)
                logger.verbose(`Tg: New subscriber: ${chatId}`);
            } else {
                this.bot.sendMessage(chatId, "Unrecognized command. Supported commands: start");
            }
        });
    }

    // send a given msg to all registered users
    sendMessage(msg: string) {
        logger.verbose(`Tg: Sending message: ${msg}`);
        for (let chatId of this.subscribers) {
            this.bot.sendMessage(chatId, msg).catch((err: any) => {
                logger.error(`Tg: Error sending msg to ${chatId}`);
                logger.error(`Tg: Error sending message: ${err.message}`);
            }).then(() => {
                logger.verbose(`Tg: Message sent to ${chatId}`);
            })
        }
    }
}
