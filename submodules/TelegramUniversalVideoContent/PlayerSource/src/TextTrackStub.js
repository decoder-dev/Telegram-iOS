
export class TextTrackStub extends EventTarget {
    constructor(kind = '', label = '', language = '') {
        super();
        this.kind = kind;
        this.label = label;
        this.language = language;
        this.mode = 'disabled'; // 'disabled', 'hidden', or 'showing'
        this.cues = new TextTrackCueListStub();
        this.activeCues = new TextTrackCueListStub();
    }

    addCue(cue) {
        this.cues._add(cue);
    }

    removeCue(cue) {
        this.cues._remove(cue);
    }
}

export class TextTrackCueListStub {
    constructor() {
        this._cues = [];
    }

    get length() {
        return this._cues.length;
    }

    item(index) {
        return this._cues[index];
    }

    getCueById(id) {
        return this._cues.find(cue => cue.id === id) || null;
    }

    _add(cue) {
        this._cues.push(cue);
    }

    _remove(cue) {
        const index = this._cues.indexOf(cue);
        if (index !== -1) {
        this._cues.splice(index, 1);
        }
    }

    [Symbol.iterator]() {
        return this._cues[Symbol.iterator]();
    }
}

export class TextTrackListStub extends EventTarget {
    constructor() {
        super();
        this._tracks = [];
    }

    get length() {
        return this._tracks.length;
    }

    item(index) {
        return this._tracks[index];
    }

    // Players index the list like a DOM TextTrackList (`textTracks[i].kind`), so mirror the
    // tracks as numeric own properties; without them hls.js reads `undefined.kind`.
    _sync() {
        const previous = this._indexed || 0;
        for (let i = 0; i < this._tracks.length; i++) {
            this[i] = this._tracks[i];
        }
        for (let i = this._tracks.length; i < previous; i++) {
            delete this[i];
        }
        this._indexed = this._tracks.length;
    }

    getTrackById(id) {
        return this._tracks.find(track => track.id === id) || null;
    }

    _add(track) {
        this._tracks.push(track);
        this._sync();
        const event = new Event('addtrack');
        event.track = track;
        this.dispatchEvent(event);
    }

    _remove(track) {
        const index = this._tracks.indexOf(track);
        if (index !== -1) {
            this._tracks.splice(index, 1);
            this._sync();
            const event = new Event('removetrack');
            event.track = track;
            this.dispatchEvent(event);
        }
    }

    [Symbol.iterator]() {
        return this._tracks[Symbol.iterator]();
    }
}
