(() => {
  const dialog = document.querySelector('.photo-modal');
  if (!dialog || typeof dialog.showModal !== 'function') return;

  const image = dialog.querySelector('img');
  const caption = dialog.querySelector('.photo-modal-caption');
  const count = dialog.querySelector('.photo-modal-count');
  const previous = dialog.querySelector('.photo-modal-previous');
  const next = dialog.querySelector('.photo-modal-next');
  const photographs = [...document.querySelectorAll('.archive-photograph')].map(figure => ({
    link: figure.querySelector('.archive-image-link'),
    caption: figure.querySelector('figcaption > span').textContent.trim()
  }));
  if (!photographs.length) return;

  previous.hidden = next.hidden = photographs.length < 2;
  let current = 0;
  let opener;

  function showPhotograph(index) {
    current = (index + photographs.length) % photographs.length;
    const photograph = photographs[current];
    const link = photograph.link;
    image.src = link.href;
    image.alt = link.dataset.photoAlt;
    image.width = Number(link.dataset.photoWidth);
    image.height = Number(link.dataset.photoHeight);
    caption.textContent = photograph.caption;
    count.textContent = `Photograph ${current + 1} of ${photographs.length}`;
    dialog.setAttribute('aria-label', 'Larger photograph of ' + link.dataset.photoName);
  }

  document.querySelectorAll('[data-photo-modal]').forEach(link => {
    link.addEventListener('click', event => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const index = photographs.findIndex(photo => photo.link.closest('figure') === link.closest('figure'));
      if (index < 0) return;
      event.preventDefault();
      opener = link;
      showPhotograph(index);
      dialog.showModal();
      document.body.classList.add('photo-modal-open');
    });
  });

  previous.addEventListener('click', () => showPhotograph(current - 1));
  next.addEventListener('click', () => showPhotograph(current + 1));
  dialog.addEventListener('keydown', event => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    showPhotograph(current + (event.key === 'ArrowRight' ? 1 : -1));
  });

  dialog.addEventListener('click', event => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) {
      dialog.close();
    }
  });

  dialog.addEventListener('close', () => {
    document.body.classList.remove('photo-modal-open');
    if (opener?.isConnected) opener.focus({preventScroll: true});
  });
})();
