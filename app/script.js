'use strict';

// const { click } = require('@testing-library/user-event/dist/click');

///////////////////////////////////////
// Modal window

const modal = document.querySelector('.modal');
const overlay = document.querySelector('.overlay');
const btnCloseModal = document.querySelector('.btn--close-modal');
const btnsOpenModal = document.querySelectorAll('.btn--show-modal');

const btnscrollto = document.querySelector('.btn--scroll-to');
const section1 = document.querySelector('#section--1');

const nav = document.querySelector(`.nav`);
//////////////////////////////////
// functions
const openModal = function (e) {
  // prevent the defaukt of tha anchor tag
  e.preventDefault();
  modal.classList.remove('hidden');
  overlay.classList.remove('hidden');
};

const closeModal = function () {
  modal.classList.add('hidden');
  overlay.classList.add('hidden');
};

btnsOpenModal.forEach((ele, i) => {
  ele.addEventListener('click', openModal);
});

btnCloseModal.addEventListener('click', closeModal);
overlay.addEventListener('click', closeModal);

document.addEventListener('keydown', function (e) {
  if (e.key === 'Escape' && !modal.classList.contains('hidden')) {
    closeModal();
  }
});

//////////////////////////////////////
// implementing smooth scrolling/////////
btnscrollto.addEventListener('click', function (e) {
  section1.scrollIntoView({
    behavior: 'smooth',
  });
});

///////////////////////////////////////
// using event delegation to implement the smooth scrolling on the page navigation
// 1. attach an event hadler to the common parent element
// 2. determine which element initiate the click
// const navLinks = document.querySelector('.nav__links');

// function handlClick(e) {
//   if (e.target.classList.contains('nav__link')) {
//     e.preventDefault();
//     const id = e.target.getAttribute('href');
//     document.querySelector(id).scrollIntoView({
//       behavior: 'smooth',
//     });
//   }
// }
// navLinks.addEventListener(`click`, handlClick);

document.querySelector('.nav__links').addEventListener('click', function (e) {
  //matching strategy
  if (e.target.classList.contains('nav__link')) {
    e.preventDefault();
    const id = e.target.getAttribute('href');
    document.querySelector(id).scrollIntoView({
      behavior: 'smooth',
    });
  }
});

///////////////////////////
//building tabbed components
// const tabs = document.querySelectorAll('.operations__tab');
const tabsContainer = document.querySelector('.operations__tab-container');
const tabs = document.querySelectorAll('.operations__tab'); //returns a nodelist, which is lke an array but not vompleterly an array
const tabs2 = tabsContainer.children; //returns an HTML collection which sadly, you cannot loop over
const tabscontent = document.querySelectorAll('.operations__content');

tabsContainer.addEventListener('click', function (e) {
  const clicked = e.target.closest('.operations__tab');
  if (!clicked) return;
  //removing the active classes
  tabs.forEach(ele => ele.classList.remove('operations__tab--active'));
  tabscontent.forEach(ele =>
    ele.classList.remove(`operations__content--active`)
  );
  // active tab
  clicked.classList.add('operations__tab--active');

  //activate contest area
  document
    .querySelector(`.operations__content--${clicked.dataset.tab}`)
    .classList.add('operations__content--active');
});

// menu fade animation

const handler = function (ev, opa) {
  if (ev.target.classList.contains('nav__link')) {
    const link = ev.target;
    const linksiblings = link.closest('.nav').querySelectorAll('.nav__link');
    const logo = link.closest('.nav').querySelector('.nav__logo');

    linksiblings.forEach(function (ele) {
      if (ele !== link) {
        ele.style.setProperty('opacity', opa);
      }
    });
    //
  }
};
nav.addEventListener('mouseover', function (ev) {
  handler(ev, 0.5);
});
nav.addEventListener('mouseout', function (ev) {
  handler(ev, 1);
});

////////////sticky nav
const stickyNav = function (entries) {
  const [entry] = entries;
  if (!entry.isIntersecting) {
    nav.classList.add('sticky');
  } else nav.classList.remove('sticky');
};
const header = document.querySelector('.header');
const headerobserver = new IntersectionObserver(stickyNav, {
  root: null,
  threshold: 0,
  rootMargin: '-90px',
});
if (window.screen.availWidth > 700) {
  headerobserver.observe(header);
} else {
  headerobserver.unobserve(header);
}

/////////// reveal sections
const allsections = document.querySelectorAll('.section');

const revealSection = function (entries, observer) {
  const [entry] = entries;

  if (!entry.isIntersecting) return;
  entry.target.classList.remove('section--hidden');
  observer.unobserve(entry.target);
};
const sectionObserver = new IntersectionObserver(revealSection, {
  root: null,
  threshold: 0.15,
});

allsections.forEach(function (section) {
  sectionObserver.observe(section);
  // section.classList.add('section--hidden');
});

//////lazy loading images
const imgtg = document.querySelectorAll(`img[data-src]`);

const lazyimg = function (entries) {
  const [entry] = entries;
  // console.log(entry);
  if (!entry.isIntersecting) return;
  //replace the src attribute data.src
  // let entsrc= entry.target.getAttribute("src")
  // let entDatasrc = entry.target.dataset.src
  // entsrc = entDatasrc
  entry.target.src = entry.target.dataset.src;
  entry.target.addEventListener('load', function () {
    entry.target.classList.remove('lazy-img');
  });
  imgobs.unobserve(entry.target);
};

const imgobs = new IntersectionObserver(lazyimg, {
  root: null,
  threshold: 0,
  rootMargin: '200px',
});
imgtg.forEach(function (img) {
  imgobs.observe(img);
});

/////////slider component

const slider1 = function () {
  const btnLeft = document.querySelector(`.slider__btn--left`);
  const btnRight = document.querySelector(`.slider__btn--right`);
  const slides = document.querySelectorAll('.slide');
  const dotcontainer = document.querySelector('.dots');

  // functions
  const createdots = function () {
    slides.forEach(function (_, ind) {
      dotcontainer.insertAdjacentHTML(
        'beforeend',
        `<button class="dots__dot" data-slide="${ind}"></button>`
      );
    });
  };

  const activatedots = function (slide) {
    document.querySelectorAll('.dots__dot').forEach(function (ele, nd) {
      ele.classList.remove('dots__dot--active');
      document
        .querySelector(`.dots__dot[data-slide="${slide}"]`)
        .classList.add('dots__dot--active');
    });
  };

  let currentslide = 0;
  const maxSlides = slides.length - 1;

  const gotoslide = function (slide) {
    slides.forEach((slid, ind) => {
      slid.style.setProperty(
        `transform`,
        `translateX(${100 * (ind - slide)}%)`
      );
    });
  };

  //next slide

  const nextslide = function () {
    if (currentslide === maxSlides) {
      currentslide = 0;
    } else {
      currentslide++;
    }
    gotoslide(currentslide);
    activatedots(currentslide);
  };
  ///previous slides
  const prevslide = function () {
    if (currentslide === 0) {
      currentslide = maxSlides;
    } else {
      currentslide--;
    }
    gotoslide(currentslide);
    activatedots(currentslide);
  };

  const init = function () {
    gotoslide(0);
    createdots();
    activatedots(0);
  };
  init();
  // evevn handlers
  btnRight.addEventListener(`click`, nextslide);
  btnLeft.addEventListener(`click`, prevslide);

  document.addEventListener(`keydown`, function (e) {
    if (e.key === 'ArrowLeft') prevslide();
    e.key === 'ArrowRight' && nextslide();
  });

  dotcontainer.addEventListener(`click`, function (e) {
    if (e.target.classList.contains('dots__dot')) {
      const slides = e.target.dataset.slide;

      gotoslide(slides);
      activatedots(slides);
    }
  });
};
slider1();
